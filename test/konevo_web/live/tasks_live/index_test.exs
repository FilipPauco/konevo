defmodule KonevoWeb.TasksLive.IndexTest do
  use KonevoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Konevo.Factory
  import Konevo.TasksFixtures

  alias Konevo.Tasks

  defp org_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}

  describe "task tree" do
    setup :register_and_log_in_user_with_org

    test "new task form renders task relationship and metadata live selects", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      company = insert(:company, organization: org, user: scope.user)
      contact = insert(:contact, organization: org, user: scope.user, company: company)

      {:ok, view, _html} =
        live(
          org_conn(conn, org),
          ~p"/tasks/new?contact_id=#{contact.id}&company_id=#{company.id}"
        )

      assert has_element?(view, "#task_contact_id_live_select_component")
      assert has_element?(view, "#task_company_id_live_select_component")
      assert has_element?(view, "#task_task_type_id_live_select_component")
      assert has_element?(view, "#task_priority_live_select_component")
      assert has_element?(view, "#task_status_live_select_component")
      assert has_element?(view, "#task_parent_task_id_live_select_component")
      assert has_element?(view, "#task_depends_on_task_id_live_select_component")
      assert has_element?(view, "h1", "Tasks")
      assert has_element?(view, "#task_task_type_id_live_select_component input[value='Task']")
      assert has_element?(view, "#task_task_type_id-select-icon[style*='color:']")
      assert has_element?(view, "#task_priority-select-icon[style*='color:']")
      assert has_element?(view, "#task_status-select-icon[style*='color:']")

      for select_id <- [
            "task_task_type_id_live_select_component",
            "task_priority_live_select_component",
            "task_status_live_select_component",
            "task_parent_task_id_live_select_component",
            "task_depends_on_task_id_live_select_component"
          ] do
        assert has_element?(view, "##{select_id} input.input")
        refute has_element?(view, "##{select_id} input[class*='border-base-content/15']")
      end

      _ = :sys.get_state(view.pid)
      assert has_element?(view, "#task_task_type_id_live_select_component input[value='Task']")

      {:ok, task_types} = Tasks.list_task_types(scope)
      task_type = Enum.find(task_types, &(&1.name == "Task"))

      view
      |> form("#task-form", task: %{task_type_id: Integer.to_string(task_type.id)})
      |> render_change()

      assert has_element?(view, "#task_task_type_id_live_select_component input[value='Task']")
    end

    test "includes Epics as parents but excludes them from dependencies", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      task_type =
        insert(:task_type,
          organization: org,
          name: "Relationship Task",
          is_parent_only: false
        )

      epic_type =
        insert(:task_type,
          organization: org,
          name: "Relationship Epic",
          is_parent_only: true
        )

      task = task_fixture(scope, %{title: "Eligible relationship task", task_type: task_type})
      epic = task_fixture(scope, %{title: "Excluded relationship epic", task_type: epic_type})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks/new")
      _ = :sys.get_state(view.pid)

      view
      |> element("#task_parent_task_id_text_input")
      |> render_click()

      assert has_element?(
               view,
               "#task_parent_task_id_live_select_component [data-idx]",
               task.title
             )

      assert has_element?(
               view,
               "#task_parent_task_id_live_select_component [data-idx]",
               epic.title
             )

      assert has_element?(
               view,
               "#task_parent_task_id_live_select_component [class~='icon-[tabler--menu-2]']"
             )

      assert has_element?(
               view,
               "#task_parent_task_id_live_select_component [class~='icon-[tabler--crown]']"
             )

      assert has_element?(
               view,
               "#task_parent_task_id_live_select_component [class~='icon-[tabler--menu-2]']"
             )

      view
      |> element("#task_depends_on_task_id_text_input")
      |> render_click()

      assert has_element?(
               view,
               "#task_depends_on_task_id_live_select_component [data-idx]",
               task.title
             )

      refute has_element?(
               view,
               "#task_depends_on_task_id_live_select_component [data-idx]",
               epic.title
             )

      assert has_element?(
               view,
               "#task_depends_on_task_id_live_select_component [class~='icon-[tabler--menu-2]']"
             )
    end

    test "opens a subtask loading row immediately before children render", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      parent = task_fixture(scope, %{title: "Parent task"})
      child = task_fixture(scope, %{title: "Child task", parent_task: parent})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks")
      _ = :sys.get_state(view.pid)

      html =
        view
        |> element("button[phx-click][aria-label='Toggle children']")
        |> render_click()

      assert html =~ ~s(id="tasks-loading-children-#{parent.id}-0")

      _ = :sys.get_state(view.pid)
      html = render(view)

      assert html =~ child.title
      refute html =~ ~s(id="tasks-loading-children-#{parent.id}-0")
    end

    @tag role: :member
    test "deletes a task without children for a member", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      task = task_fixture(scope, %{title: "Leaf task"})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks")
      _ = :sys.get_state(view.pid)

      view
      |> element("#tasks-delete-#{task.id}")
      |> render_click()

      assert has_element?(view, "#tasks-delete-confirmation")
      assert has_element?(view, "#tasks-confirm-delete")

      view
      |> element("#tasks-confirm-delete")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(scope, task.id) end
    end

    test "creates a task from the task form", %{conn: conn, org: org, scope: scope} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks/new")

      view
      |> form("#task-form",
        task: %{title: "Created from tasks page", due_date: "2026-08-20T09:00"}
      )
      |> render_submit()

      assert_patch(view, ~p"/tasks")

      assert Enum.any?(
               Tasks.list_tasks(scope) |> elem(0),
               &(&1.title == "Created from tasks page")
             )
    end

    test "filters the task list by status", %{conn: conn, org: org, scope: scope} do
      done_task = task_fixture(scope, %{title: "Completed filter task", status: :done})
      open_task = task_fixture(scope, %{title: "Open filter task", status: :open})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks?statuses=done")
      _ = :sys.get_state(view.pid)

      assert has_element?(view, "#tasks-#{done_task.id}")
      refute has_element?(view, "#tasks-#{open_task.id}")
    end

    test "renders task rows with mobile card structure", %{conn: conn, org: org, scope: scope} do
      task = task_fixture(scope, %{title: "Mobile task card"})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks")
      _ = :sys.get_state(view.pid)

      assert has_element?(view, "#tasks-#{task.id}.task-mobile-card")
      assert has_element?(view, "#tasks-#{task.id} .task-mobile-card-title")
      assert has_element?(view, "#tasks-#{task.id} .task-mobile-status")
      assert has_element?(view, "#tasks-#{task.id} .task-mobile-priority")
    end

    test "completes a task from the task list", %{conn: conn, org: org, scope: scope} do
      task = task_fixture(scope, %{title: "Complete me"})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks")
      _ = :sys.get_state(view.pid)

      view
      |> element("button[phx-click='complete'][phx-value-id='#{task.id}']")
      |> render_click()

      assert Tasks.get_task!(scope, task.id).status == :done
    end

    test "updates a task's status and priority inline", %{conn: conn, org: org, scope: scope} do
      task = task_fixture(scope, %{title: "Update me", priority: :normal})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks")
      _ = :sys.get_state(view.pid)

      view
      |> element(
        "button[phx-click='update_status'][phx-value-id='#{task.id}'][phx-value-status='in_progress']"
      )
      |> render_click()

      assert Tasks.get_task!(scope, task.id).status == :in_progress

      view
      |> element(
        "button[phx-click='update_priority'][phx-value-id='#{task.id}'][phx-value-priority='urgent']"
      )
      |> render_click()

      assert Tasks.get_task!(scope, task.id).priority == :urgent
    end

    test "searches, filters by priority, and clears task filters", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      match = task_fixture(scope, %{title: "Urgent project task", priority: :urgent})
      miss = task_fixture(scope, %{title: "Routine task", priority: :normal})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks")
      _ = :sys.get_state(view.pid)

      view
      |> form("#task-search-form", q: "Urgent")
      |> render_submit()

      assert has_element?(view, "#tasks-#{match.id}")
      refute has_element?(view, "#tasks-#{miss.id}")

      view
      |> render_hook("clear_search", %{})

      view
      |> element("#task-priority-filter input[phx-value-priority='urgent']")
      |> render_click()

      assert has_element?(view, "#tasks-#{match.id}")
      refute has_element?(view, "#tasks-#{miss.id}")

      view |> render_hook("clear_filters", %{})
      assert_push_event(view, "date_range:clear", %{})
      assert has_element?(view, "#tasks-#{match.id}")
      assert has_element?(view, "#tasks-#{miss.id}")
    end

    test "hides the footer when filters return no tasks", %{conn: conn, org: org, scope: scope} do
      _task = task_fixture(scope, %{title: "Existing task"})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks")
      _ = :sys.get_state(view.pid)

      view
      |> form("#task-search-form", q: "No matching task")
      |> render_submit()

      assert has_element?(view, "#tasks-empty")
      refute has_element?(view, "#tasks-footer")
    end

    test "archives and restores a task from the task list", %{conn: conn, org: org, scope: scope} do
      task = task_fixture(scope, %{title: "Archive task"})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks")
      _ = :sys.get_state(view.pid)

      view |> render_hook("archive", %{"id" => task.id})
      assert Tasks.get_task!(scope, task.id).archived_at

      {:ok, archived_view, _html} = live(org_conn(conn, org), ~p"/tasks?archived=archived")
      _ = :sys.get_state(archived_view.pid)

      archived_view |> render_hook("restore", %{"id" => task.id})
      refute Tasks.get_task!(scope, task.id).archived_at
    end

    test "updates task due date from the drawer", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      task = task_fixture(scope, %{title: "Drawer task"})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks/#{task.id}")
      _ = render_async(view, 1_000)

      assert has_element?(view, "#task-due-date-#{task.id}.pl-8")
      assert has_element?(view, "#task-due-date-#{task.id}[class~='border-base-content/40']")
      assert has_element?(view, "#task-due-date-icon-#{task.id}")
      assert has_element?(view, "#status-pill-#{task.id}-drawer > button.h-8.w-full")
      assert has_element?(view, "#priority-pill-#{task.id}-drawer button.h-8")

      assert has_element?(
               view,
               "#priority-pill-#{task.id}-drawer button[style*='background-color']"
             )

      view
      |> form("#task-due-date-form-#{task.id}", task: %{due_date: "2026-08-25T14:30"})
      |> render_change()

      assert Tasks.get_task!(scope, task.id).due_date == ~U[2026-08-25 14:30:00Z]
    end

    test "renames a task from the drawer", %{conn: conn, org: org, scope: scope} do
      task = task_fixture(scope, %{title: "Original task title"})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/tasks/#{task.id}")
      _ = render_async(view, 1_000)

      view |> element("#edit-task-title-#{task.id}") |> render_click()

      assert has_element?(view, "#task-title-edit-form-#{task.id}")

      view
      |> form("#task-title-edit-form-#{task.id}", task: %{title: "Renamed task title"})
      |> render_submit()

      assert Tasks.get_task!(scope, task.id).title == "Renamed task title"
      refute has_element?(view, "#task-title-edit-form-#{task.id}")
      assert has_element?(view, "#task-drawer-title-#{task.id}")
    end
  end
end
