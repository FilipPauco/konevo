defmodule Konevo.ShowcaseTest do
  use Konevo.DataCase, async: false

  import Ecto.Query
  import Konevo.Factory

  alias Konevo.Automation.{Sequence, TaskApproval}
  alias Konevo.Companies.Company
  alias Konevo.Contacts.Contact
  alias Konevo.Deals.Deal
  alias Konevo.Inbox.EmailThread
  alias Konevo.Messaging.MessageDraft
  alias Konevo.Showcase
  alias Konevo.Tasks.Task

  setup do
    user = insert(:user)
    organization = insert(:organization)
    _membership = insert(:membership, user: user, organization: organization, role: :owner)

    previous_enabled = System.get_env("KONEVO_SHOWCASE_DATA")
    previous_slug = System.get_env("KONEVO_SHOWCASE_ORG_SLUG")
    System.put_env("KONEVO_SHOWCASE_DATA", "true")
    System.put_env("KONEVO_SHOWCASE_ORG_SLUG", organization.slug)

    on_exit(fn ->
      restore_env("KONEVO_SHOWCASE_DATA", previous_enabled)
      restore_env("KONEVO_SHOWCASE_ORG_SLUG", previous_slug)
    end)

    %{organization: organization}
  end

  test "seeds and clears only showcase records", %{organization: organization} do
    assert {:ok, %{companies: 5, contacts: 5, deals: 5, workflows: 3}} = Showcase.seed()

    assert Repo.aggregate(showcase_records(Company, organization.id), :count, :id) == 5
    assert Repo.aggregate(showcase_records(Contact, organization.id), :count, :id) == 5
    assert Repo.aggregate(showcase_records(Deal, organization.id), :count, :id) == 5
    assert Repo.aggregate(showcase_records(Task, organization.id), :count, :id) == 6
    assert Repo.aggregate(showcase_sequences(organization.id), :count, :id) == 3
    assert Repo.aggregate(TaskApproval, :count, :id) == 2
    assert Repo.aggregate(MessageDraft, :count, :id) == 2

    assert Repo.aggregate(
             from(thread in EmailThread,
               where:
                 thread.organization_id == ^organization.id and
                   like(thread.thread_id_gmail, "konevo-showcase-%")
             ),
             :count,
             :id
           ) == 15

    assert {:ok, :ok} = Showcase.clear()

    assert Repo.aggregate(showcase_records(Company, organization.id), :count, :id) == 0
    assert Repo.aggregate(showcase_records(Contact, organization.id), :count, :id) == 0
    assert Repo.aggregate(showcase_records(Deal, organization.id), :count, :id) == 0
    assert Repo.aggregate(showcase_records(Task, organization.id), :count, :id) == 0
    assert Repo.aggregate(showcase_sequences(organization.id), :count, :id) == 0
    assert Repo.aggregate(TaskApproval, :count, :id) == 0
    assert Repo.aggregate(MessageDraft, :count, :id) == 0
  end

  test "requires an explicit environment confirmation" do
    System.delete_env("KONEVO_SHOWCASE_DATA")

    assert_raise RuntimeError, ~r/KONEVO_SHOWCASE_DATA=true/, fn ->
      Showcase.seed()
    end
  end

  defp showcase_records(schema, organization_id) do
    from(record in schema,
      where:
        record.organization_id == ^organization_id and
          record.archive_reason == "konevo-showcase-data"
    )
  end

  defp showcase_sequences(organization_id) do
    from(sequence in Sequence,
      where:
        sequence.organization_id == ^organization_id and
          fragment("?->>'showcase' = 'true'", sequence.trigger_config)
    )
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
