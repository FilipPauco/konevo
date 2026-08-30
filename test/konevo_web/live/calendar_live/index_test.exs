defmodule KonevoWeb.CalendarLive.IndexTest do
  use KonevoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Konevo.Factory

  defp org_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}

  describe "calendar planner" do
    setup :register_and_log_in_user_with_org

    test "mounts the planner shell with calendar controls", %{conn: conn, org: org} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/calendar")

      assert has_element?(view, "#planner-calendar-shell")

      assert has_element?(
               view,
               "#planner-calendar-shell[data-loading-events-title='Loading events']"
             )

      assert has_element?(view, "#planner-calendar-shell[data-calendar-view='dayGridMonth']")
      assert has_element?(view, "[data-calendar-view='dayGridMonth']")
      assert has_element?(view, "[data-calendar-view='timeGridWeek']")
      assert has_element?(view, "[data-calendar-view='timeGridDay']")
      assert has_element?(view, "[data-calendar-view='listWeek']")
      assert has_element?(view, "#calendar-mobile-view-select[data-calendar-view-select]")
      assert has_element?(view, "#calendar-mobile-filters-toggle[data-calendar-source-toggle]")
      assert has_element?(view, "#calendar-source-panel")
      assert has_element?(view, "#calendar-mobile-summary")
      assert has_element?(view, "[data-calendar-source='task'][class~='border-base-content/20']")
      assert has_element?(view, "[data-calendar-source='task'][class~='text-base-content']")
      assert has_element?(view, "[data-calendar-source='google_calendar']")
      assert has_element?(view, "[data-calendar-source='deal_action']")
      assert has_element?(view, "[data-calendar-source='deal_close']")
    end

    test "loads a shared calendar view and date from the URL", %{conn: conn, org: org} do
      {:ok, view, _html} =
        live(
          org_conn(conn, org),
          ~p"/calendar?view=list&date=2026-08-17&sources=task,deal_action"
        )

      assert has_element?(view, "#planner-calendar-shell[data-calendar-view='listWeek']")

      assert has_element?(
               view,
               "#planner-calendar-shell[data-calendar-initial-date='2026-08-17']"
             )

      assert has_element?(view, "[data-calendar-source='task'][data-active='true']")
      assert has_element?(view, "[data-calendar-source='google_calendar'][data-active='false']")
    end

    test "adds selected calendar sources to the URL", %{conn: conn, org: org} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/calendar")
      date = Date.to_iso8601(Date.utc_today())

      view
      |> render_hook("calendar_sources_changed", %{"sources" => ["task", "deal_action"]})

      assert_patch(
        view,
        ~p"/calendar?#{[view: "month", date: date, sources: "task,deal_action"]}"
      )
    end

    test "preloads the initial month payload for the calendar hook", %{
      conn: conn,
      org: org,
      user: user
    } do
      insert(:task,
        title: "Initial calendar task",
        due_date: DateTime.new!(Date.utc_today(), ~T[12:00:00], "Etc/UTC"),
        organization: org,
        created_by: user
      )

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/calendar")

      assert has_element?(view, "#planner-calendar-shell[data-initial-calendar]")
      assert render(view) =~ "Initial calendar task"
    end

    test "loads task and deal events when the visible range changes", %{
      conn: conn,
      org: org,
      user: user
    } do
      contact = insert(:contact, organization: org, user: user)
      stage = insert(:deal_stage, organization: org)

      task =
        insert(:task,
          title: "Visible calendar task",
          due_date: ~U[2026-08-15 12:00:00Z],
          organization: org,
          created_by: user,
          contact: contact
        )

      deal =
        insert(:deal,
          title: "Visible follow-up",
          next_action_due_date: ~U[2026-08-16 09:00:00Z],
          expected_close_date: ~D[2026-08-20],
          organization: org,
          contact: contact,
          stage: stage,
          owner: user,
          created_by: user
        )

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/calendar")

      view
      |> render_hook("calendar_range_changed", %{
        "start" => "2026-08-01T00:00:00Z",
        "end" => "2026-09-01T00:00:00Z",
        "request_id" => "range-1",
        "view" => "listWeek",
        "date" => "2026-08-17"
      })

      assert_push_event(view, "calendar:events", %{
        events: events,
        range: %{start: "2026-08-01", end: "2026-09-01"},
        request_id: "range-1"
      })

      assert_patch(view, ~p"/calendar?view=list&date=2026-08-17")

      task_event_id = "task-#{task.id}"
      deal_action_event_id = "deal-action-#{deal.id}"
      deal_close_event_id = "deal-close-#{deal.id}"

      assert %{id: ^task_event_id, extendedProps: %{source: "task"}} =
               Enum.find(events, &(&1.id == task_event_id))

      assert %{id: ^deal_action_event_id, extendedProps: %{source: "deal_action"}} =
               Enum.find(events, &(&1.id == deal_action_event_id))

      assert %{id: ^deal_close_event_id, extendedProps: %{source: "deal_close"}} =
               Enum.find(events, &(&1.id == deal_close_event_id))
    end

    test "opens a visible task in the calendar drawer", %{conn: conn, org: org, user: user} do
      task =
        insert(:task,
          organization: org,
          created_by: user,
          due_date: ~U[2026-08-15 12:00:00Z]
        )

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/calendar")

      view
      |> render_hook("open_calendar_task", %{"id" => task.id})

      assert_patch(
        view,
        ~p"/calendar/tasks/#{task.id}?#{[view: "month", date: Date.to_iso8601(Date.utc_today())]}"
      )
    end

    test "shows an error for an invalid visible range", %{conn: conn, org: org} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/calendar")

      view
      |> render_hook("calendar_range_changed", %{
        "start" => "not-a-date",
        "end" => "also-not-a-date",
        "request_id" => "range-invalid"
      })

      assert_push_event(view, "calendar:events", %{request_id: "range-invalid"})
      assert has_element?(view, "#flash-error")
    end
  end
end
