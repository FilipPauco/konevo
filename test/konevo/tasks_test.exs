defmodule Konevo.TasksTest do
  use Konevo.DataCase, async: true

  import Konevo.Factory
  import Konevo.TasksFixtures

  alias Konevo.Accounts.Scope
  alias Konevo.Tasks
  alias Konevo.Tasks.Task

  defp build_scope(role \\ :owner) do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: role)
    Scope.for_user_in_org(user, org, membership)
  end

  setup do
    %{scope: build_scope(:owner)}
  end

  # ---------------------------------------------------------------------------
  # list_tasks/2
  # ---------------------------------------------------------------------------

  describe "list_tasks/2" do
    test "returns tasks scoped to org", %{scope: scope} do
      t1 = task_fixture(scope)
      t2 = task_fixture(scope)

      other_scope = build_scope()
      _hidden = task_fixture(other_scope)

      {tasks, total} = Tasks.list_tasks(scope)
      ids = Enum.map(tasks, & &1.id)

      assert t1.id in ids
      assert t2.id in ids
      assert total == 2
    end

    test "does not return another org's tasks", %{scope: scope} do
      other_scope = build_scope()
      other_task = task_fixture(other_scope)

      {tasks, _total} = Tasks.list_tasks(scope)
      ids = Enum.map(tasks, & &1.id)

      refute other_task.id in ids
    end

    test "filters by status atom", %{scope: scope} do
      task_fixture(scope, %{status: :open})
      task_fixture(scope, %{status: :done})

      {tasks, total} = Tasks.list_tasks(scope, status: :open)
      assert total == 1
      assert hd(tasks).status == :open
    end

    test "filters by status list", %{scope: scope} do
      task_fixture(scope, %{status: :open})
      task_fixture(scope, %{status: :in_progress})
      task_fixture(scope, %{status: :done})

      {tasks, total} = Tasks.list_tasks(scope, status: [:open, :in_progress])
      assert total == 2
      assert Enum.all?(tasks, &(&1.status in [:open, :in_progress]))
    end

    test "filters by company", %{scope: scope} do
      company = insert(:company, organization: scope.org, user: scope.user)
      visible = task_fixture(scope, %{company: company})
      _hidden = task_fixture(scope)

      {tasks, total} = Tasks.list_tasks(scope, company_id: company.id)

      assert total == 1
      assert hd(tasks).id == visible.id
    end

    test "filters overdue tasks", %{scope: scope} do
      past = DateTime.add(DateTime.utc_now(:second), -86_400)
      future = DateTime.add(DateTime.utc_now(:second), 86_400)

      overdue = task_fixture(scope, %{due_date: past, status: :open})
      _upcoming = task_fixture(scope, %{due_date: future, status: :open})

      {tasks, _} = Tasks.list_tasks(scope, overdue: true)
      assert length(tasks) == 1
      assert hd(tasks).id == overdue.id
    end

    test "paginates results", %{scope: scope} do
      Enum.each(1..5, fn _ -> task_fixture(scope) end)

      {page1, total} = Tasks.list_tasks(scope, page: 1, per_page: 2)
      {page2, _} = Tasks.list_tasks(scope, page: 2, per_page: 2)

      assert total == 5
      assert length(page1) == 2
      assert length(page2) == 2
      refute Enum.any?(page1, fn t -> t.id in Enum.map(page2, & &1.id) end)
    end

    test "returns empty list when no tasks", %{scope: scope} do
      {tasks, total} = Tasks.list_tasks(scope)
      assert tasks == []
      assert total == 0
    end
  end

  describe "list_calendar_tasks/3" do
    test "returns active tasks due inside the range", %{scope: scope} do
      starts_at = ~U[2026-07-01 00:00:00Z]
      ends_at = ~U[2026-08-01 00:00:00Z]

      visible = task_fixture(scope, %{title: "Visible", due_date: ~U[2026-07-07 12:00:00Z]})
      _done = task_fixture(scope, %{due_date: ~U[2026-07-08 12:00:00Z], status: :done})
      _outside = task_fixture(scope, %{due_date: ~U[2026-08-02 12:00:00Z]})

      other_scope = build_scope()
      _other = task_fixture(other_scope, %{due_date: ~U[2026-07-09 12:00:00Z]})

      assert {:ok, tasks} = Tasks.list_calendar_tasks(scope, starts_at, ends_at)
      assert Enum.map(tasks, & &1.id) == [visible.id]
    end
  end

  describe "task timelines" do
    test "list_tasks_for_contact/3 returns direct and deal-linked tasks", %{scope: scope} do
      contact = insert(:contact, organization: scope.org, user: scope.user)
      stage = insert(:deal_stage, organization: scope.org)
      deal = insert(:deal, organization: scope.org, contact: contact, stage: stage)

      direct =
        task_fixture(scope, %{
          title: "Direct contact task",
          contact: contact,
          due_date: ~U[2026-07-20 09:00:00Z]
        })

      via_deal =
        task_fixture(scope, %{
          title: "Deal contact task",
          deal: deal,
          due_date: ~U[2026-07-21 09:00:00Z]
        })

      other_contact = insert(:contact, organization: scope.org, user: scope.user)
      _hidden = task_fixture(scope, %{contact: other_contact})

      assert {:ok, tasks} = Tasks.list_tasks_for_contact(scope, contact)
      assert Enum.map(tasks, & &1.id) == [via_deal.id, direct.id]
    end

    test "list_tasks_for_company/3 returns direct company tasks", %{scope: scope} do
      company = insert(:company, organization: scope.org, user: scope.user)

      direct =
        task_fixture(scope, %{
          company: company,
          due_date: ~U[2026-07-20 09:00:00Z]
        })

      other_company = insert(:company, organization: scope.org, user: scope.user)
      _hidden = task_fixture(scope, %{company: other_company})

      assert {:ok, tasks} = Tasks.list_tasks_for_company(scope, company)
      assert Enum.map(tasks, & &1.id) == [direct.id]
    end
  end

  # ---------------------------------------------------------------------------
  # task tree support
  # ---------------------------------------------------------------------------

  describe "task tree support" do
    test "list_task_types/1 creates default org task types", %{scope: scope} do
      assert {:ok, task_types} = Tasks.list_task_types(scope)

      names = Enum.map(task_types, & &1.name)
      assert names == ["Epic", "Task"]
      assert Enum.find(task_types, &(&1.name == "Epic")).is_parent_only
      refute Enum.find(task_types, &(&1.name == "Task")).is_parent_only
    end

    test "create_task/2 accepts string-keyed form params", %{scope: scope} do
      assert {:ok, task_types} = Tasks.list_task_types(scope)
      task_type = Enum.find(task_types, &(&1.name == "Task"))
      company = insert(:company, organization: scope.org, user: scope.user)

      assert {:ok, task} =
               Tasks.create_task(scope, %{
                 "title" => "Form task",
                 "description" => "",
                 "due_date" => "2026-06-27T18:12",
                 "parent_task_id" => "",
                 "priority" => "normal",
                 "status" => "open",
                 "company_id" => Integer.to_string(company.id),
                 "task_type_id" => Integer.to_string(task_type.id)
               })

      assert task.title == "Form task"
      assert task.task_type_id == task_type.id
      assert task.company_id == company.id
      assert task.due_date == ~U[2026-06-27 18:12:00Z]
    end

    test "create_task/2 derives company from contact", %{scope: scope} do
      company = insert(:company, organization: scope.org, user: scope.user)
      contact = insert(:contact, organization: scope.org, user: scope.user, company: company)

      assert {:ok, task} =
               Tasks.create_task(scope, %{
                 title: "Contact follow-up",
                 due_date: ~U[2026-06-27 18:12:00Z],
                 contact_id: contact.id
               })

      assert task.company_id == company.id
    end

    test "create_task/2 files email tasks without relations under Other epic", %{scope: scope} do
      thread = insert(:email_thread, organization: scope.org)
      email = insert(:email, organization: scope.org, thread: thread)

      assert {:ok, task} =
               Tasks.create_task(scope, %{
                 title: "Reply from thread",
                 due_date: ~U[2026-06-27 18:12:00Z],
                 source_email_id: email.id,
                 source_thread_id: thread.id
               })

      parent = Tasks.get_task!(scope, task.parent_task_id)

      assert parent.title == "Other"
      assert parent.task_type.name == "Epic"
      assert parent.company_id == nil
      assert parent.contact_id == nil
      assert task.source_email_id == email.id
      assert task.source_thread_id == thread.id
    end

    test "create_task/2 files contact email tasks under company epic when available", %{
      scope: scope
    } do
      company = insert(:company, organization: scope.org, user: scope.user, name: "Acme")
      contact = insert(:contact, organization: scope.org, user: scope.user, company: company)
      thread = insert(:email_thread, organization: scope.org, contact: contact)
      email = insert(:email, organization: scope.org, thread: thread)

      assert {:ok, task} =
               Tasks.create_task(scope, %{
                 title: "Prepare proposal",
                 due_date: ~U[2026-06-27 18:12:00Z],
                 source_email_id: email.id,
                 source_thread_id: thread.id,
                 contact_id: contact.id
               })

      parent = Tasks.get_task!(scope, task.parent_task_id)

      assert parent.title == "Company - Acme"
      assert parent.company_id == company.id
      assert parent.contact_id == nil
      assert task.contact_id == contact.id
      assert task.company_id == company.id
    end

    test "create_task/2 reuses the same email parent epic", %{scope: scope} do
      company = insert(:company, organization: scope.org, user: scope.user, name: "Acme")
      thread = insert(:email_thread, organization: scope.org)
      first_email = insert(:email, organization: scope.org, thread: thread)
      second_email = insert(:email, organization: scope.org, thread: thread)

      assert {:ok, first} =
               Tasks.create_task(scope, %{
                 title: "First email task",
                 due_date: ~U[2026-06-27 18:12:00Z],
                 source_email_id: first_email.id,
                 source_thread_id: thread.id,
                 company_id: company.id
               })

      assert {:ok, second} =
               Tasks.create_task(scope, %{
                 title: "Second email task",
                 due_date: ~U[2026-06-28 18:12:00Z],
                 source_email_id: second_email.id,
                 source_thread_id: thread.id,
                 company_id: company.id
               })

      assert first.parent_task_id == second.parent_task_id
    end

    test "list_task_types/1 removes unused legacy default types", %{scope: scope} do
      insert(:task_type, organization: scope.org, name: "Milestone")
      insert(:task_type, organization: scope.org, name: "Section")

      assert {:ok, task_types} = Tasks.list_task_types(scope)

      names = Enum.map(task_types, & &1.name)
      assert "Task" in names
      assert "Epic" in names
      refute "Milestone" in names
      refute "Section" in names
    end

    test "create_task/2 assigns default task type and sibling position", %{scope: scope} do
      due = DateTime.add(DateTime.utc_now(:second), 86_400)

      assert {:ok, first} = Tasks.create_task(scope, %{title: "First", due_date: due})
      assert {:ok, second} = Tasks.create_task(scope, %{title: "Second", due_date: due})

      assert first.task_type_id
      assert first.position == 0
      assert second.position == 1
    end

    test "create_task/2 rejects parent-only task types under a parent", %{scope: scope} do
      due = DateTime.add(DateTime.utc_now(:second), 86_400)
      assert {:ok, task_types} = Tasks.list_task_types(scope)
      epic_type = Enum.find(task_types, & &1.is_parent_only)
      task_type = Enum.find(task_types, &(not &1.is_parent_only))
      parent = task_fixture(scope, %{task_type: task_type})

      assert {:error, :invalid_parent_task} =
               Tasks.create_task(scope, %{
                 title: "Nested epic",
                 due_date: due,
                 parent_task_id: parent.id,
                 task_type_id: epic_type.id
               })
    end

    test "update_task/3 rejects changing a child task to a parent-only type", %{scope: scope} do
      assert {:ok, task_types} = Tasks.list_task_types(scope)
      epic_type = Enum.find(task_types, & &1.is_parent_only)
      task_type = Enum.find(task_types, &(not &1.is_parent_only))
      parent = task_fixture(scope, %{task_type: task_type})
      child = task_fixture(scope, %{parent_task: parent, task_type: task_type})

      assert {:error, :invalid_parent_task} =
               Tasks.update_task(scope, child, %{task_type_id: epic_type.id})
    end

    test "list_tree_tasks/2 returns direct children with tree metadata", %{scope: scope} do
      parent = task_fixture(scope, %{title: "Parent", position: 0})
      child = task_fixture(scope, %{title: "Child", parent_task: parent, position: 0})
      _grandchild = task_fixture(scope, %{title: "Grandchild", parent_task: child, position: 0})
      _sibling = task_fixture(scope, %{title: "Sibling", position: 1})

      assert {:ok, roots} = Tasks.list_tree_tasks(scope)
      parent_row = Enum.find(roots, &(&1.id == parent.id))

      assert parent_row.has_children?
      assert parent_row.child_count == 1
      assert parent_row.depth == 0

      assert {:ok, children} = Tasks.list_tree_tasks(scope, parent_task_id: parent.id, depth: 1)
      assert Enum.map(children, & &1.id) == [child.id]
      assert hd(children).depth == 1
      assert hd(children).has_children?
    end

    test "list_tree_tasks/2 derives parent status and progress from children", %{scope: scope} do
      parent = task_fixture(scope, %{title: "Parent", status: :open})
      task_fixture(scope, %{title: "Done child", parent_task: parent, status: :done})
      task_fixture(scope, %{title: "Open child", parent_task: parent, status: :open})

      assert {:ok, roots} = Tasks.list_tree_tasks(scope)
      parent_row = Enum.find(roots, &(&1.id == parent.id))

      assert parent_row.status_derived?
      assert parent_row.effective_status == :in_progress
      assert parent_row.child_count == 2
      assert parent_row.completed_child_count == 1
      assert parent_row.open_child_count == 1
    end

    test "list_tree_tasks/2 exposes blocking dependency counts", %{scope: scope} do
      task = task_fixture(scope)
      done_dependency = task_fixture(scope, %{status: :done})
      open_dependency = task_fixture(scope, %{status: :open})

      assert {:ok, _} = Tasks.add_dependency(scope, task, done_dependency)
      assert {:ok, _} = Tasks.add_dependency(scope, task, open_dependency)

      assert {:ok, roots} = Tasks.list_tree_tasks(scope)
      row = Enum.find(roots, &(&1.id == task.id))

      assert row.dependency_count == 2
      assert row.blocking_dependency_count == 1
      assert row.blocked?
    end

    test "add_dependency/3 records task dependency", %{scope: scope} do
      task = task_fixture(scope)
      depends_on = task_fixture(scope)

      assert {:ok, dependency} = Tasks.add_dependency(scope, task, depends_on)
      assert dependency.task_id == task.id
      assert dependency.depends_on_task_id == depends_on.id
    end

    test "add_dependency/3 rejects another org dependency", %{scope: scope} do
      task = task_fixture(scope)
      other_scope = build_scope()
      other_task = task_fixture(other_scope)

      assert {:error, :unauthorized} = Tasks.add_dependency(scope, task, other_task)
    end

    test "add_dependency/3 rejects dependency cycles", %{scope: scope} do
      first = task_fixture(scope)
      second = task_fixture(scope)

      assert {:ok, _dependency} = Tasks.add_dependency(scope, first, second)
      assert {:error, :dependency_cycle} = Tasks.add_dependency(scope, second, first)
    end

    test "update_task/3 rejects parent tree cycles", %{scope: scope} do
      parent = task_fixture(scope)
      child = task_fixture(scope, %{parent_task: parent})

      assert {:error, :invalid_parent_task} =
               Tasks.update_task(scope, parent, %{parent_task_id: child.id})
    end
  end

  # ---------------------------------------------------------------------------
  # get_task!/2
  # ---------------------------------------------------------------------------

  describe "get_task!/2" do
    test "returns the task for correct scope", %{scope: scope} do
      task = task_fixture(scope)
      result = Tasks.get_task!(scope, task.id)
      assert result.id == task.id
    end

    test "preloads source email and thread", %{scope: scope} do
      thread = insert(:email_thread, organization: scope.org)
      email = insert(:email, organization: scope.org, thread: thread)
      task = task_fixture(scope, %{source_email: email, source_thread: thread})

      result = Tasks.get_task!(scope, task.id)

      assert result.source_email.id == email.id
      assert result.source_thread.id == thread.id
    end

    test "raises when task belongs to another org", %{scope: scope} do
      other_scope = build_scope()
      other_task = task_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn ->
        Tasks.get_task!(scope, other_task.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # create_task/2
  # ---------------------------------------------------------------------------

  describe "create_task/2" do
    test "creates a task with valid attrs", %{scope: scope} do
      due = DateTime.add(DateTime.utc_now(:second), 86_400)

      assert {:ok, %Task{title: "Call client"}} =
               Tasks.create_task(scope, %{title: "Call client", due_date: due})
    end

    test "associates task with scope org and user", %{scope: scope} do
      due = DateTime.add(DateTime.utc_now(:second), 86_400)
      {:ok, task} = Tasks.create_task(scope, %{title: "X", due_date: due})

      assert task.organization_id == scope.org.id
      assert task.created_by_id == scope.user.id
    end

    test "returns error changeset when title is missing", %{scope: scope} do
      due = DateTime.add(DateTime.utc_now(:second), 86_400)
      assert {:error, %Ecto.Changeset{}} = Tasks.create_task(scope, %{due_date: due})
    end

    test "returns error changeset when due_date is missing", %{scope: scope} do
      assert {:error, %Ecto.Changeset{}} = Tasks.create_task(scope, %{title: "X"})
    end

    test "returns unauthorized for viewer" do
      scope = build_scope(:viewer)
      assert {:error, :unauthorized} = Tasks.create_task(scope, %{})
    end
  end

  # ---------------------------------------------------------------------------
  # update_task/3
  # ---------------------------------------------------------------------------

  describe "update_task/3" do
    test "updates with valid attrs", %{scope: scope} do
      task = task_fixture(scope)
      assert {:ok, updated} = Tasks.update_task(scope, task, %{title: "Updated"})
      assert updated.title == "Updated"
    end

    test "rejects direct status changes for parent tasks", %{scope: scope} do
      parent = task_fixture(scope)
      task_fixture(scope, %{parent_task: parent})

      assert {:error, :parent_status_is_derived} =
               Tasks.update_task(scope, parent, %{status: :in_progress})
    end

    test "returns error changeset for blank title", %{scope: scope} do
      task = task_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Tasks.update_task(scope, task, %{title: ""})
    end

    test "returns unauthorized for viewer" do
      owner_scope = build_scope(:owner)
      task = task_fixture(owner_scope)

      viewer = insert(:user)
      membership = insert(:membership, user: viewer, organization: owner_scope.org, role: :viewer)
      viewer_scope = Scope.for_user_in_org(viewer, owner_scope.org, membership)

      assert {:error, :unauthorized} = Tasks.update_task(viewer_scope, task, %{title: "Hacked"})
    end
  end

  # ---------------------------------------------------------------------------
  # complete_task/2
  # ---------------------------------------------------------------------------

  describe "complete_task/2" do
    test "sets status to done and records completed_at", %{scope: scope} do
      task = task_fixture(scope)
      assert {:ok, completed} = Tasks.complete_task(scope, task)
      assert completed.status == :done
      assert completed.completed_at != nil
    end

    test "rejects completion when dependencies are not complete", %{scope: scope} do
      task = task_fixture(scope)
      dependency = task_fixture(scope, %{status: :open})

      assert {:ok, _} = Tasks.add_dependency(scope, task, dependency)
      assert {:error, :task_has_open_dependencies} = Tasks.complete_task(scope, task)
    end

    test "rejects completion when child tasks are not complete", %{scope: scope} do
      parent = task_fixture(scope)
      task_fixture(scope, %{parent_task: parent, status: :open})

      assert {:error, :task_has_open_children} = Tasks.complete_task(scope, parent)
    end
  end

  # ---------------------------------------------------------------------------
  # delete_task/2
  # ---------------------------------------------------------------------------

  describe "delete_task/2" do
    test "deletes the task for owner", %{scope: scope} do
      task = task_fixture(scope)
      assert {:ok, _} = Tasks.delete_task(scope, task)

      assert_raise Ecto.NoResultsError, fn ->
        Tasks.get_task!(scope, task.id)
      end
    end

    test "returns unauthorized for viewer" do
      owner_scope = build_scope(:owner)
      task = task_fixture(owner_scope)

      viewer = insert(:user)
      membership = insert(:membership, user: viewer, organization: owner_scope.org, role: :viewer)
      viewer_scope = Scope.for_user_in_org(viewer, owner_scope.org, membership)

      assert {:error, :unauthorized} = Tasks.delete_task(viewer_scope, task)
    end

    test "recursively deletes children and grandchildren", %{scope: scope} do
      parent = task_fixture(scope, %{title: "Parent"})
      child = task_fixture(scope, %{title: "Child", parent_task: parent})
      grandchild = task_fixture(scope, %{title: "Grandchild", parent_task: child})

      assert {:ok, _} = Tasks.delete_task(scope, parent)

      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(scope, parent.id) end
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(scope, child.id) end
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(scope, grandchild.id) end
    end

    test "returns has_contact_or_deal when task has a contact", %{scope: scope} do
      contact = insert(:contact, organization: scope.org)
      task = task_fixture(scope, %{contact: contact})

      assert {:error, :has_contact_or_deal} = Tasks.delete_task(scope, task)

      # task must still exist
      assert Tasks.get_task!(scope, task.id)
    end

    test "returns has_contact_or_deal when task has a deal", %{scope: scope} do
      deal = insert(:deal, organization: scope.org)
      task = task_fixture(scope, %{deal: deal})

      assert {:error, :has_contact_or_deal} = Tasks.delete_task(scope, task)

      assert Tasks.get_task!(scope, task.id)
    end

    test "returns has_dependents when another task depends on this one", %{scope: scope} do
      blocker = task_fixture(scope, %{title: "Blocker"})
      dependent = task_fixture(scope, %{title: "Dependent"})

      assert {:ok, _} = Tasks.add_dependency(scope, dependent, blocker)

      assert {:error, :has_dependents} = Tasks.delete_task(scope, blocker)

      # both tasks must still exist
      assert Tasks.get_task!(scope, blocker.id)
      assert Tasks.get_task!(scope, dependent.id)
    end

    test "deletes task when it depends on others (not blocked)", %{scope: scope} do
      dependency = task_fixture(scope, %{title: "Dependency"})
      task = task_fixture(scope, %{title: "Task"})

      assert {:ok, _} = Tasks.add_dependency(scope, task, dependency)

      assert {:ok, _} = Tasks.delete_task(scope, task)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(scope, task.id) end
      # dependency itself is unaffected
      assert Tasks.get_task!(scope, dependency.id)
    end
  end

  # ---------------------------------------------------------------------------
  # count_tasks_by_status/1
  # ---------------------------------------------------------------------------

  describe "count_tasks_by_status/1" do
    test "returns counts grouped by status", %{scope: scope} do
      task_fixture(scope, %{status: :open})
      task_fixture(scope, %{status: :open})
      task_fixture(scope, %{status: :done})

      counts = Tasks.count_tasks_by_status(scope)

      assert counts[:open] == 2
      assert counts[:done] == 1
    end

    test "excludes another org's tasks", %{scope: scope} do
      other_scope = build_scope()
      task_fixture(other_scope, %{status: :open})

      counts = Tasks.count_tasks_by_status(scope)
      assert Map.get(counts, :open, 0) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # Task.changeset/2 — schema-level validations
  # ---------------------------------------------------------------------------

  describe "Task.changeset/2" do
    test "requires title" do
      due = DateTime.utc_now(:second)
      changeset = Task.changeset(%Task{}, %{due_date: due})
      assert "can't be blank" in errors_on(changeset).title
    end

    test "requires due_date" do
      changeset = Task.changeset(%Task{}, %{title: "X"})
      assert "can't be blank" in errors_on(changeset).due_date
    end

    test "defaults status to open" do
      due = DateTime.utc_now(:second)
      changeset = Task.changeset(%Task{}, %{title: "X", due_date: due})
      assert Ecto.Changeset.get_field(changeset, :status) == :open
    end

    test "sets completed_at when status changed to done" do
      due = DateTime.utc_now(:second)
      changeset = Task.changeset(%Task{}, %{title: "X", due_date: due, status: :done})
      assert Ecto.Changeset.get_field(changeset, :completed_at) != nil
    end

    test "rejects invalid status" do
      due = DateTime.utc_now(:second)
      changeset = Task.changeset(%Task{}, %{title: "X", due_date: due, status: :ghost})
      assert errors_on(changeset).status != []
    end

    test "rejects invalid priority" do
      due = DateTime.utc_now(:second)
      changeset = Task.changeset(%Task{}, %{title: "X", due_date: due, priority: :mega_urgent})
      assert errors_on(changeset).priority != []
    end
  end
end
