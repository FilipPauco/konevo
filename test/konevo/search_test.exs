defmodule Konevo.SearchTest do
  use Konevo.DataCase, async: true

  import Konevo.Factory
  import Konevo.CompaniesFixtures
  import Konevo.ContactsFixtures
  import Konevo.DealsFixtures
  import Konevo.InboxFixtures
  import Konevo.TasksFixtures

  alias Konevo.Accounts.Scope
  alias Konevo.Search

  defp build_scope do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: :owner)
    Scope.for_user_in_org(user, org, membership)
  end

  test "searches each record type and excludes another organization" do
    scope = build_scope()
    other_scope = build_scope()
    contact = contact_fixture(scope, %{first_name: "Needle", email: "needle@example.com"})
    company = company_fixture(scope, %{name: "Needleworks"})
    stage = deal_stage_fixture(scope)
    deal = deal_fixture(scope, stage, %{title: "Needle renewal"})
    task = task_fixture(scope, %{title: "Needle follow-up"})
    thread = thread_fixture(scope, %{subject: "Needle invoice"})
    hidden = contact_fixture(other_scope, %{first_name: "Needle hidden"})

    assert {:ok, results} = Search.search(scope, "Needle")

    result_keys = MapSet.new(Enum.map(results, &{&1.type, &1.id}))

    assert {:contact, contact.id} in result_keys
    assert {:company, company.id} in result_keys
    assert {:deal, deal.id} in result_keys
    assert {:task, task.id} in result_keys
    assert {:thread, thread.id} in result_keys
    refute {:contact, hidden.id} in result_keys
  end

  test "returns no records for a blank query" do
    assert {:ok, []} = Search.search(build_scope(), "  ")
  end
end
