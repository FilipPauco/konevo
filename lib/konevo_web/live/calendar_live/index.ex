defmodule KonevoWeb.CalendarLive.Index do
  use KonevoWeb, :live_view

  alias Konevo.Deals
  alias Konevo.Inbox
  alias Konevo.Tasks
  alias KonevoWeb.TasksLive.DrawerComponent

  @month_view_weeks 6
  @calendar_source_keys ~w(task google_calendar deal_action deal_close)

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    calendar_locale = calendar_locale()

    default_view =
      case get_connect_params(socket) do
        %{"viewport" => "mobile"} -> "listWeek"
        _ -> "dayGridMonth"
      end

    socket =
      socket
      |> assign(:page_title, gettext("Calendar"))
      |> assign(:loading, true)
      |> assign(:calendar_locale, calendar_locale)
      |> assign(:calendar_initial_date, Date.to_iso8601(today))
      |> assign(:calendar_view, default_view)
      |> assign(:calendar_sources, @calendar_source_keys)
      |> assign(:initial_range_loaded?, false)
      |> assign(:initial_calendar_payload, initial_calendar_payload())
      |> assign(:visible_range_label, gettext("Loading visible range"))
      |> assign(:summary, empty_summary())
      |> assign(:selected_task_id, nil)
      |> assign(:drawer_refresh, 0)
      |> assign(:visible_starts_at, nil)
      |> assign(:visible_ends_at, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    date = calendar_date(Map.get(params, "date"))
    sources = selected_calendar_sources(Map.get(params, "sources"))

    socket =
      socket
      |> assign(:selected_task_id, Map.get(params, "task_id"))
      |> assign(
        :calendar_view,
        calendar_view(Map.get(params, "view"), socket.assigns.calendar_view)
      )
      |> assign(:calendar_sources, sources)
      |> assign(:calendar_initial_date, Date.to_iso8601(date))
      |> maybe_preload_initial_range(date)

    {:noreply, socket}
  end

  def handle_event("calendar_sources_changed", %{"sources" => sources}, socket) do
    sources = selected_calendar_sources(sources)

    {:noreply,
     push_patch(socket,
       to:
         calendar_path(
           socket.assigns.calendar_view,
           socket.assigns.calendar_initial_date,
           sources
         )
     )}
  end

  @impl true
  def handle_event("calendar_range_changed", params, socket) do
    request_id = Map.get(params, "request_id")
    view = calendar_view(Map.get(params, "view"), socket.assigns.calendar_view)

    date =
      params
      |> Map.get("date")
      |> calendar_date()
      |> Date.to_iso8601()

    with {:ok, starts_at, ends_at} <- parse_range(params),
         {:ok, events, summary} <-
           load_calendar_items(socket.assigns.current_scope, starts_at, ends_at) do
      socket =
        socket
        |> assign(:loading, false)
        |> assign(:visible_starts_at, starts_at)
        |> assign(:visible_ends_at, ends_at)
        |> assign(:visible_range_label, format_range(starts_at, ends_at))
        |> assign(:summary, summary)
        |> push_event("calendar:events", %{
          events: events,
          range: calendar_payload_range(starts_at, ends_at),
          request_id: request_id
        })
        |> maybe_patch_calendar_state(view, date)

      {:noreply, socket}
    else
      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> push_event("calendar:events", %{request_id: request_id})
         |> put_flash(:error, gettext("You cannot view calendar items"))}

      _error ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> push_event("calendar:events", %{request_id: request_id})
         |> put_flash(:error, gettext("Failed to load calendar items"))}
    end
  end

  def handle_event("open_calendar_task", %{"id" => task_id}, socket) do
    Tasks.get_task!(socket.assigns.current_scope, task_id)

    {:noreply,
     push_patch(socket,
       to:
         calendar_task_path(
           task_id,
           socket.assigns.calendar_view,
           socket.assigns.calendar_initial_date,
           socket.assigns.calendar_sources
         )
     )}
  rescue
    Ecto.NoResultsError ->
      {:noreply, put_flash(socket, :error, gettext("Task not found"))}

    Ecto.Query.CastError ->
      {:noreply, put_flash(socket, :error, gettext("Task not found"))}
  end

  @impl true
  def handle_info({DrawerComponent, {:updated, _field}}, socket) do
    socket =
      socket
      |> update(:drawer_refresh, &(&1 + 1))
      |> refresh_visible_range()

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.page title={@page_title}>
        <div class="space-y-4">
          <div
            id="calendar-mobile-summary"
            phx-hook="CollapsiblePanel"
            data-open="false"
            class="calendar-mobile-summary overflow-hidden rounded-lg border border-base-content/10 bg-base-100 shadow-sm sm:hidden"
          >
            <button
              type="button"
              data-collapsible-toggle
              aria-expanded="false"
              class="flex w-full cursor-pointer items-center justify-between gap-3 px-3 py-2.5 text-left text-sm font-semibold text-base-content"
            >
              <span class="flex items-center gap-2">
                <span class="flex size-7 items-center justify-center rounded-md bg-primary/10 text-primary">
                  <.icon name="icon-[tabler--chart-bar]" class="size-4" />
                </span>
                {gettext("Calendar overview")}
              </span>
              <.icon
                name="icon-[tabler--chevron-down]"
                class="calendar-mobile-summary-chevron size-4 text-base-content/45"
              />
            </button>
            <div data-collapsible-content class="calendar-mobile-summary-content">
              <div class="grid grid-cols-4 border-t border-base-content/10 p-2">
                <.mobile_summary_metric
                  icon="icon-[tabler--checkbox]"
                  label={gettext("Tasks")}
                  value={@summary.tasks}
                  tone="task"
                  loading={@loading}
                />
                <.mobile_summary_metric
                  icon="icon-[tabler--users]"
                  label={gettext("Contacts")}
                  value={@summary.contacts}
                  tone="contact"
                  loading={@loading}
                />
                <.mobile_summary_metric
                  icon="icon-[tabler--building]"
                  label={gettext("Companies")}
                  value={@summary.companies}
                  tone="company"
                  loading={@loading}
                />
                <.mobile_summary_metric
                  icon="icon-[tabler--alert-circle]"
                  label={gettext("Overdue")}
                  value={@summary.overdue}
                  tone="risk"
                  loading={@loading}
                />
              </div>
            </div>
          </div>

          <div class="hidden gap-3 sm:grid sm:grid-cols-2 xl:grid-cols-4">
            <.summary_card
              id="calendar-summary-tasks"
              icon="icon-[tabler--checkbox]"
              label={gettext("Tasks due")}
              value={@summary.tasks}
              tone="task"
              loading={@loading}
            />
            <.summary_card
              id="calendar-summary-contacts"
              icon="icon-[tabler--users]"
              label={gettext("Contacts in view")}
              value={@summary.contacts}
              tone="contact"
              loading={@loading}
            />
            <.summary_card
              id="calendar-summary-companies"
              icon="icon-[tabler--building]"
              label={gettext("Companies in view")}
              value={@summary.companies}
              tone="company"
              loading={@loading}
            />
            <.summary_card
              id="calendar-summary-overdue"
              icon="icon-[tabler--alert-circle]"
              label={gettext("Overdue in view")}
              value={@summary.overdue}
              tone="risk"
              loading={@loading}
            />
          </div>

          <div class="h-[34rem] sm:h-[calc(100vh-17rem)]">
            <section
              id="planner-calendar-shell"
              phx-hook="FullCalendarPlanner"
              phx-update="ignore"
              data-calendar-locale={@calendar_locale}
              data-calendar-initial-date={@calendar_initial_date}
              data-calendar-view={@calendar_view}
              data-calendar-enabled-sources={Jason.encode!(@calendar_sources)}
              data-initial-calendar={@initial_calendar_payload}
              data-event-singular={gettext("1 event visible")}
              data-event-plural-label={gettext("events visible")}
              data-loading-events-title={gettext("Loading events")}
              data-no-events-title={gettext("No planned work in this range")}
              data-no-events-subtitle={gettext("Try another view or date range.")}
              class="flex h-full flex-col overflow-hidden rounded-lg border border-base-content/10 bg-base-100 shadow-sm"
            >
              <div class="flex flex-col gap-2 border-b border-base-content/10 p-2.5 sm:gap-3 sm:p-3 lg:flex-row lg:items-center lg:justify-between">
                <div class="flex min-w-0 items-center gap-2.5 sm:gap-3">
                  <div class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary sm:size-10">
                    <.icon name="icon-[tabler--calendar-week]" class="size-4 sm:size-5" />
                  </div>
                  <div class="min-w-0">
                    <h2
                      data-calendar-title
                      class="truncate text-sm font-semibold text-base-content sm:text-lg"
                    >
                      {gettext("Planner")}
                    </h2>
                    <p data-calendar-count class="mt-0.5 text-xs text-base-content/50">
                      {gettext("Loading events")}
                    </p>
                  </div>
                </div>

                <div class="flex items-center justify-between gap-2 lg:justify-end">
                  <div class="join">
                    <button
                      type="button"
                      data-calendar-action="prev"
                      class="calendar-toolbar-button btn btn-xs join-item border-base-content/15 bg-base-100 sm:btn-sm"
                      aria-label={gettext("Previous range")}
                    >
                      <.icon name="icon-[tabler--chevron-left]" class="size-4" />
                    </button>
                    <button
                      type="button"
                      data-calendar-action="today"
                      class="calendar-toolbar-button btn btn-xs join-item border-base-content/15 bg-base-100 px-2.5 sm:btn-sm sm:px-3"
                    >
                      {gettext("Today")}
                    </button>
                    <button
                      type="button"
                      data-calendar-action="next"
                      class="calendar-toolbar-button btn btn-xs join-item border-base-content/15 bg-base-100 sm:btn-sm"
                      aria-label={gettext("Next range")}
                    >
                      <.icon name="icon-[tabler--chevron-right]" class="size-4" />
                    </button>
                  </div>

                  <div class="sm:hidden">
                    <select
                      id="calendar-mobile-view-select"
                      data-calendar-view-select
                      class="select select-xs h-7 min-h-7 border-base-content/15 bg-base-100 text-xs font-semibold"
                      aria-label={gettext("Calendar view")}
                    >
                      <option :for={{view, label} <- calendar_views()} value={view}>{label}</option>
                    </select>
                  </div>

                  <div class="hidden sm:join">
                    <button
                      :for={{view, label} <- calendar_views()}
                      type="button"
                      data-calendar-view={view}
                      class="calendar-view-button calendar-toolbar-button btn btn-sm join-item border-base-content/15 bg-base-100"
                      aria-pressed="false"
                    >
                      {label}
                    </button>
                  </div>
                </div>
              </div>

              <div class="border-b border-base-content/10 px-2.5 py-2 sm:px-3">
                <button
                  id="calendar-mobile-filters-toggle"
                  type="button"
                  data-calendar-source-toggle
                  class="btn btn-xs gap-1.5 border border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30 sm:hidden"
                  aria-expanded="false"
                >
                  <.icon name="icon-[tabler--adjustments-horizontal]" class="size-3.5" />
                  {gettext("Filters")}
                  <.icon name="icon-[tabler--chevron-down]" class="size-3.5 opacity-55" />
                </button>
                <div
                  id="calendar-source-panel"
                  class="hidden w-full flex-wrap items-center gap-2 rounded-lg border border-base-content/20 bg-base-100 p-2 sm:flex sm:rounded-none sm:border-0 sm:bg-transparent sm:p-0"
                >
                  <%= for {source, label, icon} <- calendar_sources() do %>
                    <button
                      type="button"
                      data-calendar-source={source}
                      data-active={to_string(source in @calendar_sources)}
                      class="calendar-source-button inline-flex items-center gap-1.5 rounded-md border border-base-content/20 bg-base-100 px-2.5 py-1.5 text-xs font-semibold text-base-content transition-all hover:border-base-content/30"
                    >
                      <.icon name={icon} class="size-3.5" />
                      {label}
                    </button>
                  <% end %>
                </div>
              </div>

              <div class="min-h-0 flex-1 p-2 sm:p-3">
                <div data-calendar class="konevo-fullcalendar h-full"></div>
              </div>
            </section>
          </div>
        </div>
      </Layouts.page>

      <.live_component
        module={DrawerComponent}
        id="calendar-task-drawer-component"
        task_id={@selected_task_id}
        current_scope={@current_scope}
        open={@live_action == :task}
        refresh={@drawer_refresh}
        return_to={calendar_path(@calendar_view, @calendar_initial_date, @calendar_sources)}
      />
    </Layouts.app>
    """
  end

  attr(:id, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :integer, required: true)
  attr(:tone, :string, required: true)
  attr(:loading, :boolean, default: false)

  defp summary_card(assigns) do
    ~H"""
    <div id={@id} class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm">
      <div class="flex items-center justify-between gap-3">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/45">{@label}</p>
          <%= if @loading do %>
            <div class="skeleton mt-2 h-7 w-12 rounded-md"></div>
          <% else %>
            <p class="mt-1 text-2xl font-bold text-base-content">{@value}</p>
          <% end %>
        </div>
        <div class={["calendar-summary-icon", "calendar-summary-icon--#{@tone}"]}>
          <.icon name={@icon} class="size-5" />
        </div>
      </div>
    </div>
    """
  end

  attr(:icon, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :integer, required: true)
  attr(:tone, :string, required: true)
  attr(:loading, :boolean, default: false)

  defp mobile_summary_metric(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-col items-center gap-1 border-r border-base-content/10 px-1 text-center last:border-r-0">
      <span class={[
        "flex size-6 items-center justify-center rounded-md",
        mobile_summary_tone_class(@tone)
      ]}>
        <.icon name={@icon} class="size-3.5" />
      </span>
      <%= if @loading do %>
        <span class="skeleton h-4 w-5 rounded-sm" />
      <% else %>
        <span class="text-sm font-bold leading-none text-base-content">{@value}</span>
      <% end %>
      <span class="truncate text-[10px] leading-none text-base-content/50">{@label}</span>
    </div>
    """
  end

  defp mobile_summary_tone_class("task"), do: "bg-primary/10 text-primary"
  defp mobile_summary_tone_class("contact"), do: "bg-info/10 text-info"
  defp mobile_summary_tone_class("company"), do: "bg-secondary/10 text-secondary"
  defp mobile_summary_tone_class("risk"), do: "bg-error/10 text-error"
  defp mobile_summary_tone_class(_tone), do: "bg-base-200 text-base-content/60"

  defp calendar_views do
    [
      {"dayGridMonth", gettext("Month")},
      {"timeGridWeek", gettext("Week")},
      {"timeGridDay", gettext("Day")},
      {"listWeek", gettext("List")}
    ]
  end

  defp calendar_view("month", _default), do: "dayGridMonth"
  defp calendar_view("week", _default), do: "timeGridWeek"
  defp calendar_view("day", _default), do: "timeGridDay"
  defp calendar_view("list", _default), do: "listWeek"
  defp calendar_view("agenda", _default), do: "listDay"
  defp calendar_view("dayGridMonth", _default), do: "dayGridMonth"
  defp calendar_view("timeGridWeek", _default), do: "timeGridWeek"
  defp calendar_view("timeGridDay", _default), do: "timeGridDay"
  defp calendar_view("listWeek", _default), do: "listWeek"
  defp calendar_view("listDay", _default), do: "listDay"
  defp calendar_view(_view, default), do: default

  defp calendar_view_param("dayGridMonth"), do: "month"
  defp calendar_view_param("timeGridWeek"), do: "week"
  defp calendar_view_param("timeGridDay"), do: "day"
  defp calendar_view_param("listWeek"), do: "list"
  defp calendar_view_param("listDay"), do: "agenda"

  defp calendar_path(view, date, sources) do
    ~p"/calendar?#{calendar_query_params(view, date, sources)}"
  end

  defp calendar_task_path(task_id, view, date, sources) do
    ~p"/calendar/tasks/#{task_id}?#{calendar_query_params(view, date, sources)}"
  end

  defp maybe_patch_calendar_state(
         %{assigns: %{calendar_view: view, calendar_initial_date: date}} = socket,
         view,
         date
       ),
       do: socket

  defp maybe_patch_calendar_state(socket, view, date) do
    path =
      case socket.assigns.selected_task_id do
        nil -> calendar_path(view, date, socket.assigns.calendar_sources)
        task_id -> calendar_task_path(task_id, view, date, socket.assigns.calendar_sources)
      end

    push_patch(socket, to: path)
  end

  defp calendar_sources do
    [
      {"task", gettext("Tasks"), "icon-[tabler--checkbox]"},
      {"google_calendar", gettext("Google"), "icon-[tabler--brand-google]"},
      {"deal_action", gettext("Follow-ups"), "icon-[tabler--users]"},
      {"deal_close", gettext("Close dates"), "icon-[tabler--target-arrow]"}
    ]
  end

  defp calendar_query_params(view, date, sources) do
    params = [view: calendar_view_param(view), date: date]

    if sources == @calendar_source_keys do
      params
    else
      Keyword.put(params, :sources, Enum.join(sources, ","))
    end
  end

  defp selected_calendar_sources(nil), do: @calendar_source_keys

  defp selected_calendar_sources(sources) when is_list(sources) do
    normalize_calendar_sources(sources)
  end

  defp selected_calendar_sources(sources) when is_binary(sources) do
    sources
    |> String.split(",", trim: true)
    |> normalize_calendar_sources()
  end

  defp selected_calendar_sources(_sources), do: @calendar_source_keys

  defp normalize_calendar_sources(sources) do
    selected = Enum.filter(@calendar_source_keys, &(&1 in sources))

    if sources == [] or selected != [], do: selected, else: @calendar_source_keys
  end

  defp parse_range(%{"start" => start_value, "end" => end_value}) do
    with {:ok, starts_at} <- parse_datetime(start_value),
         {:ok, ends_at} <- parse_datetime(end_value) do
      {:ok, starts_at, ends_at}
    end
  end

  defp parse_range(_params), do: {:error, :invalid_range}

  defp calendar_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> Date.utc_today()
    end
  end

  defp calendar_date(_value), do: Date.utc_today()

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date_time, _offset} ->
        {:ok, date_time}

      {:error, _reason} ->
        with {:error, _reason} <- parse_naive_datetime(value),
             {:error, _reason} <- parse_date(value) do
          {:error, :invalid_datetime}
        end
    end
  end

  defp parse_datetime(_value), do: {:error, :invalid_datetime}

  defp parse_naive_datetime(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        {:ok, DateTime.from_naive!(NaiveDateTime.new!(date, ~T[00:00:00]), "Etc/UTC")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calendar_events(tasks, deal_actions, close_dates, google_events) do
    task_events = Enum.map(tasks, &task_event/1)
    google_calendar_events = Enum.map(google_events, &google_calendar_event/1)
    deal_action_events = Enum.map(deal_actions, &deal_action_event/1)
    close_date_events = Enum.map(close_dates, &deal_close_event/1)

    task_events ++ google_calendar_events ++ deal_action_events ++ close_date_events
  end

  defp task_event(task) do
    %{
      id: "task-#{task.id}",
      title: task.title,
      start: task_calendar_start(task.due_date),
      end: task_calendar_end(task.due_date),
      allDay: all_day?(task.due_date),
      url: ~p"/calendar/tasks/#{task.id}",
      className: "konevo-calendar-event",
      extendedProps: %{
        source: "task",
        typeLabel: task_type_label(task),
        taskType: task_type_key(task),
        meta: party_label(task_party(task)),
        status: Atom.to_string(task.status || :open),
        statusLabel: task_status_label(task.status || :open)
      }
    }
  end

  defp deal_action_event(deal) do
    party = deal_party(deal)

    %{
      id: "deal-action-#{deal.id}",
      title: deal.next_action || party_title(party) || gettext("Follow-up"),
      start: calendar_start(deal.next_action_due_date),
      allDay: all_day?(deal.next_action_due_date),
      url: ~p"/deals/#{deal}/edit",
      className: "konevo-calendar-event",
      extendedProps: %{
        source: "deal_action",
        typeLabel: gettext("Follow-up"),
        meta: party_label(party),
        stage: if(deal.stage, do: deal.stage.name, else: nil)
      }
    }
  end

  defp deal_close_event(deal) do
    party = deal_party(deal)

    %{
      id: "deal-close-#{deal.id}",
      title: party_title(party) || deal.title,
      start: Date.to_iso8601(deal.expected_close_date),
      allDay: true,
      url: ~p"/deals/#{deal}/edit",
      className: "konevo-calendar-event",
      extendedProps: %{
        source: "deal_close",
        typeLabel: gettext("Close target"),
        meta: close_meta(deal, party),
        stage: if(deal.stage, do: deal.stage.name, else: nil)
      }
    }
  end

  defp google_calendar_event(event) do
    %{
      id: "google-calendar-#{event["id"]}",
      title: google_event_title(event),
      start: google_event_start(event),
      end: google_event_end(event),
      allDay: google_event_all_day?(event),
      url: event["htmlLink"],
      className: "konevo-calendar-event",
      extendedProps: %{
        source: "google_calendar",
        typeLabel: gettext("Google Calendar"),
        meta: google_event_meta(event)
      }
    }
  end

  defp calendar_summary(tasks, deal_actions, close_dates) do
    parties =
      Enum.map(tasks, &task_party/1) ++
        Enum.map(deal_actions, &deal_party/1) ++ Enum.map(close_dates, &deal_party/1)

    overdue =
      Enum.count(tasks, fn task ->
        task.status in [:open, :in_progress] and
          DateTime.compare(task.due_date, DateTime.utc_now(:second)) == :lt
      end)

    %{
      tasks: length(tasks),
      contacts: unique_party_count(parties, :contact),
      companies: unique_party_count(parties, :company),
      overdue: overdue,
      total: length(tasks) + length(deal_actions) + length(close_dates)
    }
  end

  defp empty_summary do
    %{tasks: 0, contacts: 0, companies: 0, overdue: 0, total: 0}
  end

  defp maybe_preload_initial_range(%{assigns: %{initial_range_loaded?: true}} = socket, _date),
    do: socket

  defp maybe_preload_initial_range(socket, date) do
    if connected?(socket) do
      preload_initial_range(socket, date, socket.assigns.calendar_locale)
    else
      socket
    end
  end

  defp preload_initial_range(socket, date, calendar_locale) do
    {starts_at, ends_at} = initial_month_range(date, calendar_locale)

    case load_calendar_items(socket.assigns.current_scope, starts_at, ends_at) do
      {:ok, events, summary} ->
        socket
        |> assign(:initial_range_loaded?, true)
        |> assign(:loading, false)
        |> assign(:visible_starts_at, starts_at)
        |> assign(:visible_ends_at, ends_at)
        |> assign(:visible_range_label, format_range(starts_at, ends_at))
        |> assign(:summary, summary)
        |> assign(:initial_calendar_payload, initial_calendar_payload(events, starts_at, ends_at))

      {:error, :unauthorized} ->
        socket
        |> assign(:initial_range_loaded?, true)
        |> assign(:loading, false)
        |> put_flash(:error, gettext("You cannot view calendar items"))

      _error ->
        socket
        |> assign(:initial_range_loaded?, true)
        |> assign(:loading, false)
        |> put_flash(:error, gettext("Failed to load calendar items"))
    end
  end

  defp initial_month_range(today, calendar_locale) do
    starts_on =
      today
      |> beginning_of_month()
      |> beginning_of_week(calendar_first_day(calendar_locale))

    ends_on = Date.add(starts_on, @month_view_weeks * 7)

    {
      DateTime.new!(starts_on, ~T[00:00:00], "Etc/UTC"),
      DateTime.new!(ends_on, ~T[00:00:00], "Etc/UTC")
    }
  end

  defp beginning_of_month(date), do: Date.new!(date.year, date.month, 1)

  defp beginning_of_week(date, first_day) do
    date
    |> Date.day_of_week()
    |> then(&rem(&1 - first_day + 7, 7))
    |> then(&Date.add(date, -&1))
  end

  defp calendar_first_day("sk"), do: 1
  defp calendar_first_day(_locale), do: 7

  defp initial_calendar_payload(events \\ [], starts_at \\ nil, ends_at \\ nil) do
    %{
      events: events,
      range: calendar_payload_range(starts_at, ends_at)
    }
    |> Jason.encode!()
  end

  defp calendar_payload_range(nil, nil), do: nil

  defp calendar_payload_range(starts_at, ends_at) do
    %{
      start: starts_at |> DateTime.to_date() |> Date.to_iso8601(),
      end: ends_at |> DateTime.to_date() |> Date.to_iso8601()
    }
  end

  defp load_calendar_items(scope, starts_at, ends_at) do
    with {:ok, tasks} <- Tasks.list_calendar_tasks(scope, starts_at, ends_at),
         {:ok, deal_actions} <- Deals.list_calendar_deal_actions(scope, starts_at, ends_at),
         {:ok, close_dates} <-
           Deals.list_calendar_deal_close_dates(
             scope,
             DateTime.to_date(starts_at),
             DateTime.to_date(ends_at)
           ) do
      google_events = google_calendar_items(scope, starts_at, ends_at)

      {:ok, calendar_events(tasks, deal_actions, close_dates, google_events),
       calendar_summary(tasks, deal_actions, close_dates)}
    end
  end

  defp google_calendar_items(scope, starts_at, ends_at) do
    case Inbox.list_google_calendar_events(scope, starts_at, ends_at) do
      {:ok, events} -> events
      {:error, _reason} -> []
    end
  end

  defp task_party(%{contact: contact}) when not is_nil(contact), do: contact_party(contact)

  defp task_party(%{deal: %{contact: contact}}) when not is_nil(contact) do
    contact_party(contact)
  end

  defp task_party(_task), do: empty_party()

  defp deal_party(%{contact: contact}) when not is_nil(contact), do: contact_party(contact)
  defp deal_party(_deal), do: empty_party()

  defp contact_party(contact) do
    %{contact: contact, company: loaded_company(contact)}
  end

  defp empty_party, do: %{contact: nil, company: nil}

  defp loaded_company(%{company: %Ecto.Association.NotLoaded{}}), do: nil
  defp loaded_company(%{company: company}), do: company
  defp loaded_company(_contact), do: nil

  defp unique_party_count(parties, key) do
    parties
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.id)
    |> Enum.uniq()
    |> length()
  end

  defp party_title(%{contact: contact}) when not is_nil(contact), do: contact_name(contact)
  defp party_title(%{company: company}) when not is_nil(company), do: company.name
  defp party_title(_party), do: nil

  defp party_label(%{contact: nil, company: nil}), do: gettext("No linked contact or company")

  defp party_label(%{contact: contact, company: company})
       when not is_nil(contact) and not is_nil(company) do
    "#{contact_name(contact)} - #{company.name}"
  end

  defp party_label(%{contact: contact}) when not is_nil(contact), do: contact_name(contact)
  defp party_label(%{company: company}) when not is_nil(company), do: company.name

  defp contact_name(contact) do
    [contact.first_name, contact.last_name]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> case do
      "" -> contact.email || gettext("Unknown contact")
      name -> name
    end
  end

  defp close_meta(deal, %{company: company}) when not is_nil(company) do
    "#{close_value(deal)} - #{company.name}"
  end

  defp close_meta(deal, _party), do: close_value(deal)

  defp close_value(%{value: nil}), do: gettext("Expected close")

  defp close_value(deal) do
    "#{Decimal.round(deal.value, 0)} #{deal.currency || "EUR"}"
  end

  defp task_type_label(%{task_type: %{name: name}}) when is_binary(name), do: name
  defp task_type_label(_task), do: gettext("Task")

  defp task_type_key(%{task_type: %{is_parent_only: true}}), do: "epic"
  defp task_type_key(%{task_type: %{name: "Epic"}}), do: "epic"
  defp task_type_key(_task), do: "task"

  defp task_status_label(:open), do: gettext("Open")
  defp task_status_label(:in_progress), do: gettext("In progress")
  defp task_status_label(:done), do: gettext("Done")
  defp task_status_label(:cancelled), do: gettext("Cancelled")
  defp task_status_label(other), do: Phoenix.Naming.humanize(other)

  defp google_event_title(%{"summary" => title}) when is_binary(title) and title != "" do
    title
  end

  defp google_event_title(_event), do: gettext("Busy")

  defp google_event_start(%{"start" => %{"date" => date}}), do: date
  defp google_event_start(%{"start" => %{"dateTime" => date_time}}), do: date_time

  defp google_event_start(_event) do
    Date.utc_today()
    |> Date.to_iso8601()
  end

  defp google_event_end(%{"end" => %{"date" => date}}), do: date
  defp google_event_end(%{"end" => %{"dateTime" => date_time}}), do: date_time
  defp google_event_end(_event), do: nil

  defp google_event_all_day?(%{"start" => %{"date" => _date}}), do: true
  defp google_event_all_day?(_event), do: false

  defp google_event_meta(%{"location" => location}) when is_binary(location) and location != "" do
    location
  end

  defp google_event_meta(%{"organizer" => %{"email" => email}}) when is_binary(email), do: email
  defp google_event_meta(_event), do: gettext("Primary calendar")

  defp refresh_visible_range(%{assigns: %{visible_starts_at: nil}} = socket), do: socket

  defp refresh_visible_range(socket) do
    starts_at = socket.assigns.visible_starts_at
    ends_at = socket.assigns.visible_ends_at

    case load_calendar_items(socket.assigns.current_scope, starts_at, ends_at) do
      {:ok, events, summary} ->
        socket
        |> assign(:summary, summary)
        |> push_event("calendar:events", %{events: events})

      _error ->
        socket
    end
  end

  defp calendar_start(%DateTime{} = date_time) do
    if all_day?(date_time) do
      date_time |> DateTime.to_date() |> Date.to_iso8601()
    else
      DateTime.to_iso8601(date_time)
    end
  end

  defp task_calendar_start(%DateTime{} = date_time) do
    if all_day?(date_time) do
      calendar_start(date_time)
    else
      date_time
      |> DateTime.add(-1, :hour)
      |> local_datetime_iso8601()
    end
  end

  defp task_calendar_end(%DateTime{} = date_time) do
    unless all_day?(date_time), do: local_datetime_iso8601(date_time)
  end

  defp local_datetime_iso8601(%DateTime{} = date_time) do
    date_time
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_iso8601()
  end

  defp all_day?(%DateTime{hour: 0, minute: 0, second: 0}), do: true
  defp all_day?(_date_time), do: false

  defp format_range(starts_at, ends_at) do
    starts_on = DateTime.to_date(starts_at)
    ends_on = ends_at |> DateTime.to_date() |> Date.add(-1)

    if starts_on == ends_on do
      Calendar.strftime(starts_on, "%b %-d, %Y")
    else
      "#{Calendar.strftime(starts_on, "%b %-d")} - #{Calendar.strftime(ends_on, "%b %-d, %Y")}"
    end
  end

  defp calendar_locale do
    KonevoWeb.Gettext
    |> Gettext.get_locale()
    |> case do
      "sk" <> _ -> "sk"
      _locale -> "en"
    end
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
end
