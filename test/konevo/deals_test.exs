defmodule Konevo.DealsTest do
  use Konevo.DataCase, async: true

  import Konevo.Factory
  import Konevo.DealsFixtures

  alias Konevo.Accounts.Scope
  alias Konevo.Deals
  alias Konevo.Deals.{Deal, DealStage}

  defp build_scope(role \\ :owner) do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: role)
    Scope.for_user_in_org(user, org, membership)
  end

  setup do
    scope = build_scope(:owner)
    stage = deal_stage_fixture(scope, %{position: 1000})
    %{scope: scope, stage: stage}
  end

  # ---------------------------------------------------------------------------
  # DealStage
  # ---------------------------------------------------------------------------

  describe "list_stages/1" do
    test "returns stages ordered by position", %{scope: scope} do
      insert(:deal_stage, organization: scope.org, position: 2, name: "Quoted")
      insert(:deal_stage, organization: scope.org, position: 0, name: "Qualified")

      stages = Deals.list_stages(scope)
      positions = Enum.map(stages, & &1.position)

      assert positions == Enum.sort(positions)
    end

    test "does not return another org's stages", %{scope: scope} do
      other_scope = build_scope()
      _other = insert(:deal_stage, organization: other_scope.org)

      stages = Deals.list_stages(scope)
      org_ids = Enum.map(stages, & &1.organization_id) |> Enum.uniq()

      assert org_ids == [scope.org.id]
    end
  end

  describe "create_stage/2" do
    test "creates a stage with valid attrs", %{scope: scope} do
      assert {:ok, %DealStage{name: "Qualified"}} =
               Deals.create_stage(scope, %{name: "Qualified", position: 0})
    end

    test "associates the stage with the scope's org", %{scope: scope} do
      {:ok, stage} = Deals.create_stage(scope, %{name: "Quoted", position: 1})
      assert stage.organization_id == scope.org.id
    end

    test "returns error changeset when name is missing", %{scope: scope} do
      assert {:error, %Ecto.Changeset{}} = Deals.create_stage(scope, %{position: 0})
    end

    test "returns unauthorized for viewer", do: viewer_stage_unauthorized(:create)
  end

  describe "update_stage/3" do
    test "updates stage name", %{scope: scope, stage: stage} do
      assert {:ok, updated} = Deals.update_stage(scope, stage, %{name: "Renamed"})
      assert updated.name == "Renamed"
    end
  end

  describe "delete_stage/2" do
    test "deletes the stage", %{scope: scope, stage: stage} do
      assert {:ok, _} = Deals.delete_stage(scope, stage)

      assert_raise Ecto.NoResultsError, fn ->
        Deals.get_stage!(scope, stage.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Deals
  # ---------------------------------------------------------------------------

  describe "list_deals/2" do
    test "returns deals scoped to org", %{scope: scope, stage: stage} do
      d1 = deal_fixture(scope, stage, %{title: "Deal A"})
      d2 = deal_fixture(scope, stage, %{title: "Deal B"})

      other_scope = build_scope()
      other_stage = deal_stage_fixture(other_scope)
      _hidden = deal_fixture(other_scope, other_stage)

      deals = Deals.list_deals(scope)
      ids = Enum.map(deals, & &1.id)

      assert d1.id in ids
      assert d2.id in ids
      assert length(deals) == 2
    end

    test "filters by contact_id", %{scope: scope, stage: stage} do
      d1 = deal_fixture(scope, stage)
      d2 = deal_fixture(scope, stage)

      deals = Deals.list_deals(scope, contact_id: d1.contact_id)
      ids = Enum.map(deals, & &1.id)

      assert d1.id in ids
      refute d2.id in ids
    end

    test "filters by company_id through linked contacts", %{scope: scope, stage: stage} do
      company = insert(:company, organization: scope.org)

      linked_contact =
        insert(:contact, organization: scope.org, user: scope.user, company: company)

      other_contact = insert(:contact, organization: scope.org, user: scope.user)

      visible =
        insert(:deal,
          organization: scope.org,
          contact: linked_contact,
          stage: stage,
          owner: scope.user,
          created_by: scope.user
        )

      hidden =
        insert(:deal,
          organization: scope.org,
          contact: other_contact,
          stage: stage,
          owner: scope.user,
          created_by: scope.user
        )

      assert Enum.map(Deals.list_deals(scope, company_id: company.id), & &1.id) == [visible.id]
      refute hidden.id in Enum.map(Deals.list_deals(scope, company_id: company.id), & &1.id)
    end

    test "filters by stage_id", %{scope: scope, stage: stage} do
      other_stage = deal_stage_fixture(scope, %{name: "Other", position: 99})
      d1 = deal_fixture(scope, stage)
      _d2 = deal_fixture(scope, other_stage)

      deals = Deals.list_deals(scope, stage_id: stage.id)
      assert length(deals) == 1
      assert hd(deals).id == d1.id
    end

    test "filters by stage_ids", %{scope: scope, stage: stage} do
      other_stage = deal_stage_fixture(scope, %{name: "Other", position: 99})
      d1 = deal_fixture(scope, stage)
      _d2 = deal_fixture(scope, other_stage)

      deals = Deals.list_deals(scope, stage_ids: [stage.id])
      assert Enum.map(deals, & &1.id) == [d1.id]
    end

    test "filters by search", %{scope: scope, stage: stage} do
      match = deal_fixture(scope, stage, %{title: "Enterprise Rollout"})
      _miss = deal_fixture(scope, stage, %{title: "Renewal"})

      deals = Deals.list_deals(scope, search: "Enterprise")
      assert Enum.map(deals, & &1.id) == [match.id]
    end

    test "filters by value probability close date and source", %{scope: scope, stage: stage} do
      match =
        deal_fixture(scope, stage, %{
          title: "Qualified",
          value: Decimal.new("5000"),
          probability: 80,
          expected_close_date: ~D[2026-07-15],
          source: "referral"
        })

      _miss =
        deal_fixture(scope, stage, %{
          title: "Too small",
          value: Decimal.new("500"),
          probability: 20,
          expected_close_date: ~D[2026-08-15],
          source: "manual"
        })

      deals =
        Deals.list_deals(scope,
          min_value: Decimal.new("1000"),
          min_probability: 50,
          close_from: ~D[2026-07-01],
          close_to: ~D[2026-07-31],
          sources: ["referral"]
        )

      assert Enum.map(deals, & &1.id) == [match.id]
    end
  end

  describe "calendar deal queries" do
    test "returns open deal next actions inside the range", %{scope: scope, stage: stage} do
      starts_at = ~U[2026-07-01 00:00:00Z]
      ends_at = ~U[2026-08-01 00:00:00Z]

      visible =
        deal_fixture(scope, stage, %{
          title: "Follow up",
          next_action_due_date: ~U[2026-07-10 09:00:00Z]
        })

      _closed =
        deal_fixture(scope, stage, %{
          next_action_due_date: ~U[2026-07-11 09:00:00Z],
          closed_at: ~U[2026-07-11 10:00:00Z]
        })

      _outside =
        deal_fixture(scope, stage, %{next_action_due_date: ~U[2026-08-02 09:00:00Z]})

      other_scope = build_scope()
      other_stage = deal_stage_fixture(other_scope)

      _other =
        deal_fixture(other_scope, other_stage, %{next_action_due_date: ~U[2026-07-12 09:00:00Z]})

      assert {:ok, deals} = Deals.list_calendar_deal_actions(scope, starts_at, ends_at)
      assert Enum.map(deals, & &1.id) == [visible.id]
    end

    test "returns open deal close dates inside the date range", %{scope: scope, stage: stage} do
      starts_on = ~D[2026-07-01]
      ends_on = ~D[2026-08-01]

      visible =
        deal_fixture(scope, stage, %{
          title: "Close target",
          expected_close_date: ~D[2026-07-15]
        })

      _closed =
        deal_fixture(scope, stage, %{
          expected_close_date: ~D[2026-07-16],
          closed_at: ~U[2026-07-16 10:00:00Z]
        })

      _outside = deal_fixture(scope, stage, %{expected_close_date: ~D[2026-08-02]})

      assert {:ok, deals} = Deals.list_calendar_deal_close_dates(scope, starts_on, ends_on)
      assert Enum.map(deals, & &1.id) == [visible.id]
    end
  end

  describe "get_deal!/2" do
    test "returns the deal for correct scope", %{scope: scope, stage: stage} do
      deal = deal_fixture(scope, stage)
      result = Deals.get_deal!(scope, deal.id)
      assert result.id == deal.id
    end

    test "preloads stage, contact, and activities", %{scope: scope, stage: stage} do
      deal = deal_fixture(scope, stage)
      result = Deals.get_deal!(scope, deal.id)

      assert %Konevo.Deals.DealStage{} = result.stage
      assert %Konevo.Contacts.Contact{} = result.contact
      assert is_list(result.activities)
    end

    test "raises when deal belongs to another org", %{scope: scope} do
      other_scope = build_scope()
      other_stage = deal_stage_fixture(other_scope)
      other_deal = deal_fixture(other_scope, other_stage)

      assert_raise Ecto.NoResultsError, fn ->
        Deals.get_deal!(scope, other_deal.id)
      end
    end
  end

  describe "create_deal/2" do
    test "creates a deal with valid attrs", %{scope: scope, stage: stage} do
      contact = insert(:contact, organization: scope.org, user: scope.user)

      assert {:ok, %Deal{title: "New Deal"}} =
               Deals.create_deal(scope, %{
                 title: "New Deal",
                 value: "5000.00",
                 stage_id: stage.id,
                 contact_id: contact.id
               })
    end

    test "generates duplicate slugs with hyphen suffixes", %{scope: scope, stage: stage} do
      contact = insert(:contact, organization: scope.org, user: scope.user)
      attrs = %{title: "New Deal", value: "5000.00", stage_id: stage.id, contact_id: contact.id}

      assert {:ok, first} = Deals.create_deal(scope, attrs)
      assert {:ok, second} = Deals.create_deal(scope, attrs)

      assert first.slug == "new-deal"
      assert second.slug == "new-deal-1"
      assert Deals.get_deal_by_slug_or_id!(scope, second.slug).id == second.id
    end

    test "associates deal with scope org and user", %{scope: scope, stage: stage} do
      contact = insert(:contact, organization: scope.org, user: scope.user)

      {:ok, deal} =
        Deals.create_deal(scope, %{
          title: "X",
          value: "1.00",
          stage_id: stage.id,
          contact_id: contact.id
        })

      assert deal.organization_id == scope.org.id
      assert deal.created_by_id == scope.user.id
    end

    test "returns error changeset when value is missing", %{scope: scope, stage: stage} do
      contact = insert(:contact, organization: scope.org, user: scope.user)

      assert {:error, %Ecto.Changeset{}} =
               Deals.create_deal(scope, %{title: "X", stage_id: stage.id, contact_id: contact.id})
    end

    test "returns unauthorized for viewer" do
      scope = build_scope(:viewer)
      assert {:error, :unauthorized} = Deals.create_deal(scope, %{})
    end
  end

  describe "update_deal/3" do
    test "updates with valid attrs", %{scope: scope, stage: stage} do
      deal = deal_fixture(scope, stage)
      assert {:ok, updated} = Deals.update_deal(scope, deal, %{title: "Updated"})
      assert updated.title == "Updated"
      assert updated.slug == "updated"
    end

    test "records a stage_change activity when stage changes", %{scope: scope, stage: stage} do
      new_stage = deal_stage_fixture(scope, %{name: "Won", position: 99})
      deal = deal_fixture(scope, stage)

      assert {:ok, updated} = Deals.update_deal(scope, deal, %{stage_id: new_stage.id})
      assert updated.stage_id == new_stage.id

      activities = Repo.all(Ecto.assoc(updated, :activities))
      assert Enum.any?(activities, &(&1.activity_type == :stage_change))
    end

    test "returns unauthorized for viewer" do
      owner_scope = build_scope(:owner)
      stage = deal_stage_fixture(owner_scope)
      deal = deal_fixture(owner_scope, stage)

      viewer = insert(:user)
      membership = insert(:membership, user: viewer, organization: owner_scope.org, role: :viewer)
      viewer_scope = Scope.for_user_in_org(viewer, owner_scope.org, membership)

      assert {:error, :unauthorized} = Deals.update_deal(viewer_scope, deal, %{title: "Hacked"})
    end
  end

  describe "delete_deal/2" do
    test "deletes the deal for owner", %{scope: scope, stage: stage} do
      deal = deal_fixture(scope, stage)
      assert {:ok, _} = Deals.delete_deal(scope, deal)

      assert_raise Ecto.NoResultsError, fn ->
        Deals.get_deal!(scope, deal.id)
      end
    end
  end

  describe "change_deal/2" do
    test "returns a changeset", %{scope: scope, stage: stage} do
      deal = deal_fixture(scope, stage)
      assert %Ecto.Changeset{} = Deals.change_deal(deal)
    end
  end

  describe "pipeline_summary/1" do
    test "returns grouped totals per stage", %{scope: scope, stage: stage} do
      deal_fixture(scope, stage, %{value: Decimal.new("1000.00")})
      deal_fixture(scope, stage, %{value: Decimal.new("2000.00")})

      summary = Deals.pipeline_summary(scope)
      entry = Enum.find(summary, &(&1.stage_id == stage.id))

      assert entry.count == 2
      assert Decimal.equal?(entry.total_value, Decimal.new("3000.00"))
    end
  end

  describe "Deal.changeset/2" do
    test "requires title" do
      changeset = Deal.changeset(%Deal{}, %{value: "100", stage_id: 1, contact_id: 1})
      assert "can't be blank" in errors_on(changeset).title
    end

    test "requires value" do
      changeset = Deal.changeset(%Deal{}, %{title: "X", stage_id: 1, contact_id: 1})
      assert "can't be blank" in errors_on(changeset).value
    end

    test "rejects negative value" do
      changeset = Deal.changeset(%Deal{}, %{title: "X", value: "-1", stage_id: 1, contact_id: 1})
      assert errors_on(changeset).value != []
    end

    test "rejects invalid currency" do
      changeset =
        Deal.changeset(%Deal{}, %{
          title: "X",
          value: "100",
          currency: "INVALID",
          stage_id: 1,
          contact_id: 1
        })

      assert errors_on(changeset).currency != []
    end

    test "rejects probability outside 0-100" do
      changeset =
        Deal.changeset(%Deal{}, %{
          title: "X",
          value: "100",
          probability: 101,
          stage_id: 1,
          contact_id: 1
        })

      assert errors_on(changeset).probability != []
    end
  end

  defp viewer_stage_unauthorized(:create) do
    scope = build_scope(:viewer)
    assert {:error, :unauthorized} = Deals.create_stage(scope, %{name: "X", position: 0})
  end
end
