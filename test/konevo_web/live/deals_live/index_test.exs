defmodule KonevoWeb.DealsLive.IndexTest do
  use KonevoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Konevo.Factory

  alias Konevo.Accounts.Scope
  alias Konevo.Deals

  setup do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: :owner)
    scope = Scope.for_user_in_org(user, org, membership)
    conn = build_conn() |> log_in_user(user) |> org_conn(org)
    stage = insert(:deal_stage, organization: org, name: "Qualified", position: 1)

    contact =
      insert(:contact, organization: org, user: user, first_name: "Jane", last_name: "Buyer")

    %{conn: conn, contact: contact, scope: scope, stage: stage}
  end

  test "creates a deal from the modal", %{
    conn: conn,
    scope: scope,
    stage: stage
  } do
    {:ok, view, _html} = live(conn, ~p"/deals/new")

    view
    |> element("#deal_contact_id_live_select_component")
    |> render_hook("option_click", %{idx: "0"})

    view
    |> form("#deal-form",
      deal: %{
        title: "Expansion",
        value: "5000",
        currency: "EUR",
        stage_id: stage.id
      }
    )
    |> render_submit()

    _ = :sys.get_state(view.pid)
    html = render(view)

    assert html =~ "Expansion"
    assert [%{title: "Expansion"} = deal] = Deals.list_deals(scope)
    assert has_element?(view, "#deal-#{deal.id}")
  end

  test "marks contact as required and does not offer an empty selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deals/new")

    assert has_element?(view, "#deal_contact_id-label .text-error", "*")
    refute render(view) =~ "No contact"
  end

  test "uses a subtle shadow for Kanban stage collapse controls", %{conn: conn, stage: stage} do
    {:ok, view, _html} = live(conn, ~p"/deals")

    assert has_element?(view, "#stage-collapse-#{stage.id}.shadow-sm")
    refute has_element?(view, "#stage-collapse-#{stage.id}.shadow-lg")
  end

  test "renders searchable owner and source pickers", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deals/new")

    assert has_element?(view, "#deal_owner_id_live_select_component")
    assert has_element?(view, "#deal_owner_id_live_select_component input[type='text']")
    assert has_element?(view, "#deal_owner_id-select-chevron")
    assert has_element?(view, "#deal_contact_id_live_select_component input[type='text']")
    assert has_element?(view, "#deal_contact_id-select-chevron")
    assert has_element?(view, "#deal_source_live_select_component")
    assert has_element?(view, "#deal_source_live_select_component input.h-10[type='text']")
    assert has_element?(view, "#deal_title.h-10")
    assert has_element?(view, "#deal_value.h-10")
    assert has_element?(view, "#deal_currency_live_select_component input[type='text']")
    assert has_element?(view, "#deal_currency-select-chevron")
    assert has_element?(view, "#deal_expected_close_date.h-10")
  end

  test "keeps the owner email visible after validation", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/deals/new")

    view
    |> form("#deal-form", deal: %{owner_id: scope.user.id, title: "Changed"})
    |> render_change()

    assert has_element?(
             view,
             "#deal_owner_id_live_select_component input[type='text'][value='#{scope.user.email}']"
           )
  end

  test "keeps the source label visible after validation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deals/new")

    view
    |> element("#deal_source_live_select_component")
    |> render_hook("option_click", %{idx: "1"})

    view
    |> form("#deal-form", deal: %{title: "Changed"})
    |> render_change()

    assert has_element?(
             view,
             "#deal_source_live_select_component input[type='text'][value='Email']"
           )
  end

  test "shows required errors on invalid submit", %{conn: conn, stage: stage} do
    {:ok, view, _html} = live(conn, ~p"/deals/new")

    html =
      view
      |> form("#deal-form", deal: %{title: "", value: "", stage_id: stage.id})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
  end

  test "preselects the stage from the new deal URL", %{conn: conn, scope: scope} do
    stage = insert(:deal_stage, organization: scope.org, name: "Proposal", position: 2)

    {:ok, view, _html} = live(conn, ~p"/deals/new?stage_id=#{stage.id}")

    assert has_element?(view, "#stage-opt-#{stage.id}[checked]")

    assert has_element?(
             view,
             "#stage-opt-#{stage.id} + span[class~='border-base-content/40']"
           )
  end

  test "renders search and deal filters", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/deals")

    assert has_element?(view, "#deal-search-form")
    assert has_element?(view, "#deal-stage-filter-dropdown")
    assert has_element?(view, "#deal-value-filter-dropdown")
    assert has_element?(view, "#deal-probability-filter-dropdown")
    assert has_element?(view, "#deal-close-date-filter")
    assert has_element?(view, "#deal-source-filter-dropdown")
  end

  test "search event narrows the deal board", %{
    conn: conn,
    contact: contact,
    scope: scope,
    stage: stage
  } do
    match =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user,
        title: "Enterprise Expansion",
        value: Decimal.new("5000")
      )

    miss =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user,
        title: "Small Renewal",
        value: Decimal.new("5000")
      )

    {:ok, view, _html} = live(conn, ~p"/deals")

    view
    |> element("#deal-search-form")
    |> render_submit(%{q: "Enterprise"})

    assert has_element?(view, "#deal-#{match.id}")
    refute has_element?(view, "#deal-#{miss.id}")
  end

  test "loads additional deals for an individual Kanban stage", %{
    conn: conn,
    contact: contact,
    scope: scope,
    stage: stage
  } do
    deals =
      for number <- 1..26 do
        insert(:deal,
          organization: scope.org,
          contact: contact,
          stage: stage,
          owner: scope.user,
          created_by: scope.user,
          title: "Kanban deal #{number}",
          value: Decimal.new("5000")
        )
      end

    last_deal = List.last(deals)
    {:ok, view, _html} = live(conn, ~p"/deals")

    assert has_element?(view, "#kanban-load-more-#{stage.id}")
    refute has_element?(view, "#deal-#{last_deal.id}")

    view
    |> element("#kanban-load-more-#{stage.id}")
    |> render_click()

    assert has_element?(view, "#deal-#{last_deal.id}")
    refute has_element?(view, "#kanban-load-more-#{stage.id}")
  end

  test "URL filters narrow the deal board", %{
    conn: conn,
    contact: contact,
    scope: scope,
    stage: stage
  } do
    other_stage = insert(:deal_stage, organization: scope.org, name: "Lost", position: 2)

    match =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user,
        title: "Filtered Deal",
        value: Decimal.new("8000"),
        probability: 75,
        expected_close_date: ~D[2026-07-15],
        source: "referral"
      )

    miss =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: other_stage,
        owner: scope.user,
        created_by: scope.user,
        title: "Hidden Deal",
        value: Decimal.new("500"),
        probability: 20,
        expected_close_date: ~D[2026-08-15],
        source: "manual"
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/deals?#{%{stage_ids: stage.id, min_value: 1000, min_probability: 50, close_from: "2026-07-01", close_to: "2026-07-31", sources: "referral"}}"
      )

    assert has_element?(view, "#kc-#{stage.id}")
    refute has_element?(view, "#kc-#{other_stage.id}")
    assert has_element?(view, "#deal-#{match.id}")
    refute has_element?(view, "#deal-#{miss.id}")
    assert has_element?(view, "#deal-value-filter-dropdown")
    assert has_element?(view, "#deal-probability-filter-dropdown")
  end

  test "edits an existing deal", %{conn: conn, contact: contact, scope: scope, stage: stage} do
    deal =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user,
        title: "Original deal title",
        value: Decimal.new("5000")
      )

    {:ok, view, _html} = live(conn, ~p"/deals/#{deal}/edit")

    assert has_element?(
             view,
             "#deal_contact_id_live_select_component input[type='text'][value='Jane Buyer']"
           )

    view
    |> form("#deal-form", deal: %{title: "Updated deal title"})
    |> render_submit()

    assert Deals.get_deal!(scope, deal.id).title == "Updated deal title"
    assert_patch(view, ~p"/deals")
  end

  test "keeps the archived filter while editing a deal", %{
    conn: conn,
    contact: contact,
    scope: scope,
    stage: stage
  } do
    deal =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user,
        title: "Archived deal",
        value: Decimal.new("5000"),
        archived_at: DateTime.utc_now()
      )

    {:ok, view, _html} = live(conn, ~p"/deals?archived=archived")

    view
    |> element("#deal-#{deal.id} a[href='/deals/#{deal.slug}/edit?archived=archived']")
    |> render_click()

    assert_patch(view, ~p"/deals/#{deal}/edit?archived=archived")

    view
    |> form("#deal-form", deal: %{title: "Updated archived deal"})
    |> render_submit()

    assert_patch(view, ~p"/deals?archived=archived")
  end

  test "moves a deal to another Kanban stage", %{
    conn: conn,
    contact: contact,
    scope: scope,
    stage: stage
  } do
    target_stage = insert(:deal_stage, organization: scope.org, name: "Proposal", position: 2)

    deal =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user,
        value: Decimal.new("5000")
      )

    {:ok, view, _html} = live(conn, ~p"/deals")

    view
    |> render_hook("reposition-kanban", %{
      "id" => to_string(deal.id),
      "to" => %{"status" => to_string(target_stage.id)}
    })

    assert Deals.get_deal!(scope, deal.id).stage_id == target_stage.id
    assert has_element?(view, "#kanban-col-#{target_stage.id} #deal-#{deal.id}")
  end

  test "archives and restores a deal from the board", %{
    conn: conn,
    contact: contact,
    scope: scope,
    stage: stage
  } do
    deal =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user,
        value: Decimal.new("5000")
      )

    {:ok, view, _html} = live(conn, ~p"/deals")

    assert has_element?(view, "#m-deal-#{deal.id} .opacity-100")
    assert has_element?(view, "#m-deal-#{deal.id} a[aria-label='Edit deal']")
    assert has_element?(view, "#m-deal-#{deal.id} button[aria-label='Archive deal']")

    view
    |> element("#deal-#{deal.id} button[phx-click='archive_deal']")
    |> render_click()

    assert Deals.get_deal!(scope, deal.id).archived_at

    {:ok, archived_view, _html} = live(conn, ~p"/deals?archived=archived")

    archived_view
    |> element("#deal-#{deal.id} button[phx-click='restore_deal']")
    |> render_click()

    refute Deals.get_deal!(scope, deal.id).archived_at
  end

  test "deletes a deal from the board", %{
    conn: conn,
    contact: contact,
    scope: scope,
    stage: stage
  } do
    deal =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user,
        value: Decimal.new("5000")
      )

    {:ok, view, _html} = live(conn, ~p"/deals")

    view
    |> element("#deal-#{deal.id} button[phx-click='delete_deal']")
    |> render_click()

    assert_raise Ecto.NoResultsError, fn -> Deals.get_deal!(scope, deal.id) end
  end

  test "applies deal filters from the board controls", %{
    conn: conn,
    contact: contact,
    scope: scope,
    stage: stage
  } do
    match =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user,
        title: "Qualified referral",
        value: Decimal.new("5000"),
        probability: 80,
        expected_close_date: ~D[2026-08-15],
        source: "referral"
      )

    miss =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user,
        title: "Small manual deal",
        value: Decimal.new("500"),
        probability: 20,
        expected_close_date: ~D[2026-09-15],
        source: "manual"
      )

    {:ok, view, _html} = live(conn, ~p"/deals")

    view
    |> form("#deal-value-filter-form", min_value: "1000")
    |> render_submit()

    view
    |> form("#deal-probability-filter-form", min_probability: "50")
    |> render_submit()

    view
    |> render_hook("filter_date_range", %{"from" => "2026-08-01", "to" => "2026-08-31"})

    view
    |> element("#deal-source-filter-dropdown input[phx-value-source='referral']")
    |> render_click()

    assert has_element?(view, "#deal-#{match.id}")
    refute has_element?(view, "#deal-#{miss.id}")

    view |> render_hook("clear_filters", %{})
    assert_push_event(view, "date_range:clear", %{})
    assert has_element?(view, "#deal-#{match.id}")
    assert has_element?(view, "#deal-#{miss.id}")
  end

  test "shows clear filters for a search-only result", %{
    conn: conn,
    contact: contact,
    scope: scope,
    stage: stage
  } do
    match =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user,
        title: "Searchable deal"
      )

    {:ok, view, _html} = live(conn, ~p"/deals")

    view |> form("#deal-search-form", q: "Searchable") |> render_change()

    assert has_element?(view, "#deal-#{match.id}")
    assert has_element?(view, "#deals-clear-filters")
    assert has_element?(view, "#deals-filter-panel #deals-clear-filters")
    refute has_element?(view, "#deals-toolbar-actions #deals-clear-filters")

    view |> element("#deals-clear-filters") |> render_click()

    refute has_element?(view, "#deals-clear-filters")
  end

  defp org_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}
end
