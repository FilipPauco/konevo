defmodule Konevo.ArchiveTest do
  use Konevo.DataCase, async: true

  import Konevo.CompaniesFixtures
  import Konevo.ContactsFixtures
  import Konevo.DealsFixtures
  import Konevo.Factory
  import Konevo.TasksFixtures

  alias Konevo.Accounts
  alias Konevo.Accounts.Scope
  alias Konevo.Companies
  alias Konevo.Contacts
  alias Konevo.Deals
  alias Konevo.Permissions
  alias Konevo.Tasks

  defp build_scope(role \\ :owner) do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: role)
    Scope.for_user_in_org(user, org, membership)
  end

  describe "company archiving" do
    test "hides archived companies by default and supports restore" do
      scope = build_scope()
      active = company_fixture(scope, %{name: "Active Company"})
      archived = company_fixture(scope, %{name: "Archived Company"})

      assert {:ok, archived} = Companies.archive_company(scope, archived)

      {companies, 1} = Companies.list_companies(scope, [])
      assert Enum.map(companies, & &1.id) == [active.id]

      {companies, 1} = Companies.list_companies(scope, archive_filter: :archived)
      assert Enum.map(companies, & &1.id) == [archived.id]

      assert {:ok, restored} = Companies.restore_company(scope, archived)
      refute restored.archived_at

      {_companies, 2} = Companies.list_companies(scope, [])
    end
  end

  describe "contact archiving" do
    test "hides archived contacts by default and supports restore" do
      scope = build_scope()
      active = contact_fixture(scope, %{first_name: "Active"})
      archived = contact_fixture(scope, %{first_name: "Archived"})

      assert {:ok, archived} = Contacts.archive_contact(scope, archived)

      {contacts, 1} = Contacts.list_contacts(scope)
      assert Enum.map(contacts, & &1.id) == [active.id]

      {contacts, 1} = Contacts.list_contacts(scope, archive_filter: :archived)
      assert Enum.map(contacts, & &1.id) == [archived.id]

      assert {:ok, restored} = Contacts.restore_contact(scope, archived)
      refute restored.archived_at

      {_contacts, 2} = Contacts.list_contacts(scope)
    end
  end

  describe "deal archiving" do
    test "hides archived deals by default and supports restore" do
      scope = build_scope()
      stage = deal_stage_fixture(scope)
      active = deal_fixture(scope, stage, %{title: "Active Deal"})
      archived = deal_fixture(scope, stage, %{title: "Archived Deal"})

      assert {:ok, archived} = Deals.archive_deal(scope, archived)

      assert Enum.map(Deals.list_deals(scope), & &1.id) == [active.id]

      assert Enum.map(Deals.list_deals(scope, archive_filter: :archived), & &1.id) == [
               archived.id
             ]

      assert {:ok, restored} = Deals.restore_deal(scope, archived)
      refute restored.archived_at

      assert length(Deals.list_deals(scope)) == 2
    end
  end

  describe "task archiving" do
    test "archives and restores task descendants" do
      scope = build_scope()
      parent = task_fixture(scope, %{title: "Parent"})
      child = task_fixture(scope, %{title: "Child", parent_task: parent})

      assert {:ok, _parent} = Tasks.archive_task(scope, parent)

      {_tasks, 0} = Tasks.list_tasks(scope)
      {archived_tasks, 2} = Tasks.list_tasks(scope, archive_filter: :archived)
      assert MapSet.new(Enum.map(archived_tasks, & &1.id)) == MapSet.new([parent.id, child.id])

      assert Tasks.get_task!(scope, parent.id).archived_at
      assert Tasks.get_task!(scope, child.id).archived_at

      assert {:ok, _parent} = Tasks.restore_task(scope, parent)

      {tasks, 2} = Tasks.list_tasks(scope)
      assert MapSet.new(Enum.map(tasks, & &1.id)) == MapSet.new([parent.id, child.id])
    end
  end

  describe "membership archiving" do
    test "removes archived memberships from access checks and supports restore" do
      scope = build_scope()
      member = insert(:user)
      {:ok, membership} = Accounts.create_membership(member, scope.org, :member)

      assert length(Accounts.list_members(scope.org)) == 2

      assert {:ok, archived} = Accounts.archive_membership(scope.user, membership)
      assert archived.archived_at

      active_ids = Accounts.list_members(scope.org) |> Enum.map(& &1.id)
      refute membership.id in active_ids
      refute Permissions.get_membership(member, scope.org)

      {members, 1} = Accounts.list_members(scope.org, archive_filter: :archived)
      assert Enum.map(members, & &1.id) == [membership.id]

      assert {:ok, restored} = Accounts.restore_membership(archived)
      refute restored.archived_at
      assert Permissions.get_membership(member, scope.org)
    end
  end
end
