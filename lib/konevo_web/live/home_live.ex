defmodule KonevoWeb.HomeLive do
  use KonevoWeb, :live_view

  alias Konevo.Reporting

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @current_scope && @current_scope.user do %>
      <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
        <Layouts.page title={gettext("Dashboard")}>
          <%= cond do %>
            <% is_nil(@current_scope.org) -> %>
              <.dashboard_setup />
            <% @dashboard_loading? -> %>
              <.dashboard_loading />
            <% is_nil(@dashboard) -> %>
              <.dashboard_empty />
            <% true -> %>
              <.dashboard dashboard={@dashboard} />
          <% end %>
        </Layouts.page>
      </Layouts.app>
    <% else %>
      <div class="left-160 fixed inset-y-0 right-0 z-0 hidden lg:block xl:left-200">
        <svg
          viewBox="0 0 1480 957"
          fill="none"
          aria-hidden="true"
          class="absolute inset-0 h-full w-full"
          preserveAspectRatio="xMinYMid slice"
        >
          <path fill="#EE7868" d="M0 0h1480v957H0z" />
          <path
            d="M137.542 466.27c-582.851-48.41-988.806-82.127-1608.412 658.2l67.39 810 3083.15-256.51L1535.94-49.622l-98.36 8.183C1269.29 281.468 734.115 515.799 146.47 467.012l-8.928-.742Z"
            fill="#FF9F92"
          />
          <path
            d="M359.326 571.714C-104.765 215.795-428.003-32.102-1349.55 255.554l-282.3 1224.596 3047.04 722.01 312.24-1354.467C1411.25 1028.3 834.355 935.995 366.435 577.166l-7.109-5.452Z"
            fill="#E96856"
            fill-opacity=".6"
          />
          <path
            d="M1593.87 1236.88c-352.15 92.63-885.498-145.85-1244.602-613.557l-5.455-7.105C-12.347 152.31-260.41-170.8-1225-131.458l-368.63 1599.048 3057.19 704.76 130.31-935.47Z"
            fill="#C42652"
            fill-opacity=".2"
          />
          <path
            d="M1411.91 1526.93c-363.79 15.71-834.312-330.6-1085.883-863.909l-3.822-8.102C72.704 125.95-101.074-242.476-1052.01-408.907l-699.85 1484.267 2837.75 1338.01 326.02-886.44Z"
            fill="#A41C42"
            fill-opacity=".2"
          />
          <path
            d="M1116.26 1863.69c-355.457-78.98-720.318-535.27-825.287-1115.521l-1.594-8.816C185.286 163.833 112.786-237.016-762.678-643.898L-1822.83 608.665 571.922 2635.55l544.338-771.86Z"
            fill="#A41C42"
            fill-opacity=".2"
          />
        </svg>
      </div>

      <div class="px-4 py-10 sm:px-6 sm:py-28 lg:px-8 xl:px-28 xl:py-32">
        <div class="mx-auto max-w-xl lg:mx-0">
          <div class="flex items-center gap-3">
            <img src={~p"/images/logo.png"} alt="" class="size-16 object-cover" />
            <span class="text-3xl font-semibold text-primary">{gettext("Konevo")}</span>
          </div>
          <div class="mt-10 flex justify-between items-center">
            <h1 class="flex items-center text-sm font-semibold leading-6">
              {gettext("Konevo CRM")}
              <small class="badge badge-warning badge-sm ml-3">
                v{Application.spec(:konevo, :vsn)}
              </small>
            </h1>

            <div class="flex items-center gap-3">
              <.link
                href="https://github.com/FilipPauco/konevo"
                target="_blank"
                rel="noreferrer"
                class="btn btn-neutral btn-sm gap-2"
              >
                <.icon name="icon-[tabler--brand-github]" class="size-4" />
                {gettext("GitHub")}
              </.link>
              <.link href="mailto:contact@example.com" class="btn btn-primary btn-sm gap-2">
                <.icon name="icon-[tabler--mail]" class="size-4" />
                {gettext("Contact")}
              </.link>
            </div>
          </div>

          <p class="text-[2rem] mt-4 font-semibold leading-10 tracking-tighter text-balance">
            {gettext("Your entire customer pipeline, in one place.")}
          </p>

          <p class="mt-4 leading-7 text-base-content/70">
            {gettext(
              "Konevo is a modern CRM built for agencies and sales teams. Manage contacts, track deals, handle your inbox, and automate follow-ups — all from a single, fast, real-time interface."
            )}
          </p>

          <div class="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div class="group relative rounded-box px-6 py-5 text-sm font-semibold leading-6">
              <span class="absolute inset-0 rounded-box bg-base-content/5 transition group-hover:bg-base-content/20">
              </span>
              <span class="relative flex items-center gap-3 sm:flex-col sm:items-start">
                <span class="icon-[tabler--inbox] size-6 shrink-0 text-base-content/60" />
                <span>
                  {gettext("Unified Inbox")}
                  <span class="mt-1 block text-xs font-normal text-base-content/50">
                    {gettext("All conversations in one view")}
                  </span>
                </span>
              </span>
            </div>

            <div class="group relative rounded-box px-6 py-5 text-sm font-semibold leading-6">
              <span class="absolute inset-0 rounded-box bg-base-content/5 transition group-hover:bg-base-content/20">
              </span>
              <span class="relative flex items-center gap-3 sm:flex-col sm:items-start">
                <span class="icon-[tabler--briefcase] size-6 shrink-0 text-base-content/60" />
                <span>
                  {gettext("Deal Pipeline")}
                  <span class="mt-1 block text-xs font-normal text-base-content/50">
                    {gettext("Track every opportunity")}
                  </span>
                </span>
              </span>
            </div>

            <div class="group relative rounded-box px-6 py-5 text-sm font-semibold leading-6">
              <span class="absolute inset-0 rounded-box bg-base-content/5 transition group-hover:bg-base-content/20">
              </span>
              <span class="relative flex items-center gap-3 sm:flex-col sm:items-start">
                <span class="icon-[tabler--sparkles] size-6 shrink-0 text-base-content/60" />
                <span>
                  {gettext("AI Assistant")}
                  <span class="mt-1 block text-xs font-normal text-base-content/50">
                    {gettext("Smarter replies, faster close")}
                  </span>
                </span>
              </span>
            </div>
          </div>

          <div class="mt-12 grid grid-cols-1 gap-y-3 text-sm leading-6 text-base-content/60 sm:grid-cols-2">
            <div class="flex items-center gap-2">
              <span class="icon-[tabler--users] size-4 shrink-0" /> {gettext(
                "Contact & company management"
              )}
            </div>

            <div class="flex items-center gap-2">
              <span class="icon-[tabler--checkbox] size-4 shrink-0" /> {gettext(
                "Tasks & follow-up reminders"
              )}
            </div>

            <div class="flex items-center gap-2">
              <span class="icon-[tabler--chart-bar] size-4 shrink-0" /> {gettext(
                "Real-time dashboards"
              )}
            </div>

            <div class="flex items-center gap-2">
              <span class="icon-[tabler--shield-lock] size-4 shrink-0" /> {gettext(
                "Role-based access control"
              )}
            </div>
          </div>
        </div>
      </div>
      <Layouts.flash_group flash={@flash} />
    <% end %>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:dashboard, nil)
      |> assign(:dashboard_loading?, has_org?(socket.assigns.current_scope))
      |> maybe_load_dashboard()

    {:ok, socket}
  end

  defp maybe_load_dashboard(socket) do
    if connected?(socket) && has_org?(socket.assigns.current_scope) do
      scope = socket.assigns.current_scope
      start_async(socket, :dashboard, fn -> Reporting.dashboard(scope) end)
    else
      socket
    end
  end

  @impl true
  def handle_async(:dashboard, {:ok, {:ok, dashboard}}, socket) do
    {:noreply, assign(socket, dashboard: dashboard, dashboard_loading?: false)}
  end

  def handle_async(:dashboard, _result, socket) do
    {:noreply, assign(socket, dashboard: nil, dashboard_loading?: false)}
  end

  defp has_org?(%{org: %{id: _id}}), do: true
  defp has_org?(_scope), do: false

  attr(:dashboard, :map, required: true)

  defp dashboard(assigns) do
    assigns =
      assigns
      |> assign(:brief, assigns.dashboard.brief)
      |> assign(:queue, assigns.dashboard.action_queue)
      |> assign(:radar, assigns.dashboard.follow_up_radar)
      |> assign(:pipeline, assigns.dashboard.pipeline_risk)
      |> assign(:tasks, assigns.dashboard.task_commitments)

    ~H"""
    <div class="space-y-5">
      <section
        id="daily-owner-brief"
        class="rounded-lg border border-base-content/10 bg-base-100 p-5 shadow-sm"
      >
        <div class="flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
          <div class="min-w-0">
            <p class="text-xs font-semibold uppercase tracking-normal text-primary">
              {gettext("Daily owner brief")}
            </p>
            <h2 class="mt-2 text-2xl font-semibold leading-tight text-base-content">
              {gettext(
                "%{threads} need reply · %{money} at risk · %{tasks} overdue · %{deals} closing this week",
                threads: @brief.needs_reply,
                money: format_money(@brief.revenue_at_risk),
                tasks: @brief.overdue_tasks,
                deals: @brief.closing_this_week
              )}
            </h2>
          </div>
          <.link navigate={~p"/inbox"} class="btn btn-primary btn-sm gap-2">
            <.icon name="icon-[tabler--inbox]" class="size-4" />
            {gettext("Work inbox")}
          </.link>
        </div>

        <div class="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <.metric_card
            id="dashboard-metric-needs-reply"
            label={gettext("Needs reply")}
            value={to_string(@brief.needs_reply)}
            icon="icon-[tabler--mail-exclamation]"
            href={~p"/inbox"}
          />
          <.metric_card
            id="dashboard-metric-revenue-risk"
            label={gettext("Revenue at risk")}
            value={format_money(@brief.revenue_at_risk)}
            icon="icon-[tabler--cash-banknote-off]"
            href={~p"/inbox"}
          />
          <.metric_card
            id="dashboard-metric-overdue-tasks"
            label={gettext("Overdue tasks")}
            value={to_string(@brief.overdue_tasks)}
            icon="icon-[tabler--alarm]"
            href={~p"/tasks?overdue=true"}
          />
          <.metric_card
            id="dashboard-metric-closing-week"
            label={gettext("Closing this week")}
            value={to_string(@brief.closing_this_week)}
            icon="icon-[tabler--calendar-dollar]"
            href={~p"/deals"}
          />
        </div>
      </section>

      <div class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_380px]">
        <section
          id="dashboard-action-queue"
          class="rounded-lg border border-base-content/10 bg-base-100 shadow-sm"
        >
          <div class="flex items-center justify-between gap-4 border-b border-base-content/10 p-4">
            <div>
              <h2 class="text-base font-semibold">{gettext("Today's action queue")}</h2>
              <p class="mt-0.5 text-sm text-base-content/60">
                {gettext("Prioritized by unanswered leads, overdue work, and deal risk.")}
              </p>
            </div>
            <.link navigate={~p"/tasks"} class="btn btn-ghost btn-sm">
              {gettext("All tasks")}
            </.link>
          </div>

          <div class="divide-y divide-base-content/8">
            <div :if={@queue == []} class="p-8 text-center">
              <.icon name="icon-[tabler--circle-check]" class="mx-auto size-10 text-primary" />
              <p class="mt-3 font-medium">{gettext("No urgent actions right now")}</p>
              <p class="mt-1 text-sm text-base-content/60">
                {gettext("When leads go quiet, tasks slip, or deals need action, they appear here.")}
              </p>
            </div>
            <.action_queue_item :for={item <- @queue} item={item} />
          </div>
        </section>

        <aside class="space-y-5">
          <.follow_up_radar radar={@radar} />
          <.pipeline_risk pipeline={@pipeline} />
          <.task_commitments tasks={@tasks} />
        </aside>
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:href, :string, required: true)

  defp metric_card(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@href}
      class="group flex min-h-24 items-center gap-4 rounded-lg border border-base-content/10 bg-base-200/35 p-4 transition hover:border-primary/30 hover:bg-primary/5"
    >
      <span class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-base-100 text-primary shadow-sm ring-1 ring-base-content/10">
        <.icon name={@icon} class="size-5" />
      </span>
      <span class="min-w-0">
        <span class="block text-2xl font-semibold leading-none text-base-content">{@value}</span>
        <span class="mt-1 block text-sm text-base-content/60">{@label}</span>
      </span>
      <.icon
        name="icon-[tabler--arrow-right]"
        class="ml-auto size-4 text-base-content/35 transition group-hover:translate-x-0.5 group-hover:text-primary"
      />
    </.link>
    """
  end

  attr(:item, :map, required: true)

  defp action_queue_item(assigns) do
    ~H"""
    <div class="grid gap-3 p-4 transition hover:bg-base-200/45 md:grid-cols-[minmax(0,1fr)_auto] md:items-center">
      <div class="flex min-w-0 gap-3">
        <span class={[
          "mt-0.5 flex size-10 shrink-0 items-center justify-center rounded-lg",
          queue_icon_class(@item.tone)
        ]}>
          <.icon name={@item.icon} class="size-5" />
        </span>
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="truncate font-semibold text-base-content">{@item.title}</h3>
            <span
              :if={money_positive?(@item.amount)}
              class="badge badge-sm border border-primary/30 bg-primary/10 text-primary"
            >
              {format_money(@item.amount)}
            </span>
          </div>
          <p class="mt-1 truncate text-sm text-base-content/60">{@item.subtitle}</p>
          <p class="mt-1 text-xs font-medium text-base-content/50">{@item.meta}</p>
        </div>
      </div>
      <.link
        navigate={item_href(@item)}
        class="btn btn-sm btn-outline gap-2 justify-self-start md:justify-self-end"
      >
        {action_label(@item.action)}
        <.icon name="icon-[tabler--arrow-right]" class="size-4" />
      </.link>
    </div>
    """
  end

  attr(:radar, :map, required: true)

  defp follow_up_radar(assigns) do
    ~H"""
    <section
      id="follow-up-radar"
      class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <h2 class="font-semibold">{gettext("Follow-up radar")}</h2>
          <p class="mt-0.5 text-sm text-base-content/60">
            {gettext("Quiet leads that need a nudge.")}
          </p>
        </div>
        <.icon name="icon-[tabler--radar]" class="size-5 text-primary" />
      </div>
      <div class="mt-4 grid grid-cols-2 gap-2">
        <.small_stat label={gettext("24h quiet")} value={@radar.stale_24h} />
        <.small_stat label={gettext("3d quiet")} value={@radar.stale_3d} />
        <.small_stat label={gettext("7d quiet")} value={@radar.stale_7d} />
        <.small_stat label={gettext("High value quiet")} value={@radar.high_value_quiet} />
      </div>
      <.link navigate={~p"/inbox"} class="btn btn-sm btn-ghost mt-4 w-full justify-between">
        {gettext("Review follow-ups")}
        <.icon name="icon-[tabler--arrow-right]" class="size-4" />
      </.link>
    </section>
    """
  end

  attr(:pipeline, :map, required: true)

  defp pipeline_risk(assigns) do
    ~H"""
    <section
      id="pipeline-risk"
      class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <h2 class="font-semibold">{gettext("Pipeline risk")}</h2>
          <p class="mt-0.5 text-sm text-base-content/60">{gettext("Deals that need movement.")}</p>
        </div>
        <.icon name="icon-[tabler--chart-arrows]" class="size-5 text-primary" />
      </div>
      <div class="mt-4 space-y-2">
        <.risk_row
          label={gettext("Closing this month")}
          value={format_money(@pipeline.closing_this_month_value)}
        />
        <.risk_row label={gettext("Overdue next actions")} value={@pipeline.overdue_next_actions} />
        <.risk_row label={gettext("No next action")} value={@pipeline.no_next_action} />
      </div>
      <.link navigate={~p"/deals"} class="btn btn-sm btn-ghost mt-4 w-full justify-between">
        {gettext("Open pipeline")}
        <.icon name="icon-[tabler--arrow-right]" class="size-4" />
      </.link>
    </section>
    """
  end

  attr(:tasks, :map, required: true)

  defp task_commitments(assigns) do
    ~H"""
    <section
      id="task-commitments"
      class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <h2 class="font-semibold">{gettext("Task commitments")}</h2>
          <p class="mt-0.5 text-sm text-base-content/60">{gettext("What is due now and next.")}</p>
        </div>
        <.icon name="icon-[tabler--list-check]" class="size-5 text-primary" />
      </div>
      <div class="mt-4 grid grid-cols-3 gap-2">
        <.small_stat label={gettext("Overdue")} value={@tasks.overdue} />
        <.small_stat label={gettext("Today")} value={@tasks.due_today} />
        <.small_stat label={gettext("Week")} value={@tasks.due_this_week} />
      </div>
      <.link navigate={~p"/tasks"} class="btn btn-sm btn-ghost mt-4 w-full justify-between">
        {gettext("Open tasks")}
        <.icon name="icon-[tabler--arrow-right]" class="size-4" />
      </.link>
    </section>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :any, required: true)

  defp small_stat(assigns) do
    ~H"""
    <div class="rounded-lg bg-base-200/55 px-3 py-2">
      <p class="text-lg font-semibold leading-none">{@value}</p>
      <p class="mt-1 text-xs text-base-content/55">{@label}</p>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :any, required: true)

  defp risk_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3 rounded-lg bg-base-200/45 px-3 py-2 text-sm">
      <span class="text-base-content/65">{@label}</span>
      <span class="font-semibold">{@value}</span>
    </div>
    """
  end

  defp dashboard_setup(assigns) do
    ~H"""
    <div
      id="dashboard-setup"
      class="rounded-lg border border-base-content/10 bg-base-100 p-8 text-center shadow-sm"
    >
      <.icon name="icon-[tabler--building]" class="mx-auto size-10 text-primary" />
      <h2 class="mt-4 text-lg font-semibold">{gettext("Open a workspace to see your dashboard")}</h2>
      <p class="mx-auto mt-2 max-w-xl text-sm text-base-content/60">
        {gettext("The rescue dashboard uses workspace inbox, deal, and task data.")}
      </p>
    </div>
    """
  end

  defp dashboard_empty(assigns) do
    ~H"""
    <div
      id="dashboard-empty"
      class="rounded-lg border border-base-content/10 bg-base-100 p-8 text-center shadow-sm"
    >
      <.icon name="icon-[tabler--database-off]" class="mx-auto size-10 text-base-content/35" />
      <h2 class="mt-4 text-lg font-semibold">{gettext("No dashboard data yet")}</h2>
      <p class="mx-auto mt-2 max-w-xl text-sm text-base-content/60">
        {gettext(
          "Connect Gmail, add deals, or create tasks and this page becomes your daily command center."
        )}
      </p>
    </div>
    """
  end

  defp dashboard_loading(assigns) do
    ~H"""
    <div
      id="dashboard-loading"
      class="space-y-5"
      aria-busy="true"
      aria-label={gettext("Loading dashboard")}
    >
      <.dashboard_brief_skeleton />
      <div class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_380px]">
        <.dashboard_queue_skeleton />
        <div class="space-y-5">
          <.dashboard_radar_skeleton />
          <.dashboard_pipeline_skeleton />
          <.dashboard_tasks_skeleton />
        </div>
      </div>
    </div>
    """
  end

  defp dashboard_brief_skeleton(assigns) do
    ~H"""
    <section
      id="dashboard-brief-skeleton"
      class="rounded-lg border border-base-content/10 bg-base-100 p-5 shadow-sm"
    >
      <div class="flex items-start justify-between gap-4">
        <div class="space-y-3">
          <div class="skeleton h-3 w-28 rounded" /><div class="skeleton h-7 w-80 max-w-full rounded" />
        </div>
        <div class="skeleton h-8 w-28 shrink-0 rounded-lg" />
      </div>
      <div class="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <div
          :for={card <- 1..4}
          id={"dashboard-metric-skeleton-#{card}"}
          class="flex min-h-24 items-center gap-4 rounded-lg border border-base-content/10 bg-base-200/35 p-4"
        >
          <div class="skeleton size-10 shrink-0 rounded-lg" />
          <div class="space-y-2">
            <div class="skeleton h-6 w-16 rounded" /><div class="skeleton h-3 w-24 rounded" />
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp dashboard_queue_skeleton(assigns) do
    ~H"""
    <section
      id="dashboard-action-queue-skeleton"
      class="rounded-lg border border-base-content/10 bg-base-100 shadow-sm"
    >
      <div class="flex items-center justify-between gap-4 border-b border-base-content/10 p-4">
        <div class="space-y-2">
          <div class="skeleton h-5 w-40 rounded" /><div class="skeleton h-3 w-72 max-w-full rounded" />
        </div>
        <div class="skeleton h-8 w-20 rounded-lg" />
      </div>
      <div class="divide-y divide-base-content/8">
        <div
          :for={row <- 1..5}
          id={"dashboard-action-skeleton-#{row}"}
          class="grid gap-3 p-4 md:grid-cols-[minmax(0,1fr)_auto] md:items-center"
        >
          <div class="flex gap-3">
            <div class="skeleton size-10 shrink-0 rounded-lg" />
            <div class="flex-1 space-y-2">
              <div class="skeleton h-4 w-3/5 rounded" /><div class="skeleton h-3 w-4/5 rounded" /><div class="skeleton h-3 w-1/3 rounded" />
            </div>
          </div>
          <div class="skeleton h-8 w-24 rounded-lg" />
        </div>
      </div>
    </section>
    """
  end

  defp dashboard_radar_skeleton(assigns) do
    ~H"""
    <section
      id="dashboard-follow-up-radar-skeleton"
      class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
    >
      <.dashboard_panel_heading_skeleton />
      <div class="mt-4 grid grid-cols-2 gap-2">
        <div
          :for={stat <- 1..4}
          id={"dashboard-radar-stat-skeleton-#{stat}"}
          class="rounded-lg bg-base-200/55 px-3 py-2"
        >
          <div class="skeleton h-5 w-8 rounded" /><div class="skeleton mt-2 h-3 w-16 rounded" />
        </div>
      </div>
      <div class="skeleton mt-4 h-8 w-full rounded-lg" />
    </section>
    """
  end

  defp dashboard_pipeline_skeleton(assigns) do
    ~H"""
    <section
      id="dashboard-pipeline-risk-skeleton"
      class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
    >
      <.dashboard_panel_heading_skeleton />
      <div class="mt-4 space-y-2">
        <div
          :for={row <- 1..3}
          id={"dashboard-pipeline-row-skeleton-#{row}"}
          class="flex justify-between rounded-lg bg-base-200/45 px-3 py-2"
        >
          <div class="skeleton h-4 w-32 rounded" /><div class="skeleton h-4 w-12 rounded" />
        </div>
      </div>
      <div class="skeleton mt-4 h-8 w-full rounded-lg" />
    </section>
    """
  end

  defp dashboard_tasks_skeleton(assigns) do
    ~H"""
    <section
      id="dashboard-task-commitments-skeleton"
      class="rounded-lg border border-base-content/10 bg-base-100 p-4 shadow-sm"
    >
      <.dashboard_panel_heading_skeleton />
      <div class="mt-4 grid grid-cols-3 gap-2">
        <div
          :for={stat <- 1..3}
          id={"dashboard-task-stat-skeleton-#{stat}"}
          class="rounded-lg bg-base-200/55 px-3 py-2"
        >
          <div class="skeleton h-5 w-8 rounded" /><div class="skeleton mt-2 h-3 w-12 rounded" />
        </div>
      </div>
      <div class="skeleton mt-4 h-8 w-full rounded-lg" />
    </section>
    """
  end

  defp dashboard_panel_heading_skeleton(assigns) do
    ~H"""
    <div class="flex justify-between gap-3">
      <div class="space-y-2">
        <div class="skeleton h-5 w-32 rounded" /><div class="skeleton h-3 w-44 rounded" />
      </div>
      <div class="skeleton size-5 rounded" />
    </div>
    """
  end

  defp item_href(%{type: :thread, id: id}), do: ~p"/inbox/#{id}"
  defp item_href(%{type: :task, id: id}), do: ~p"/tasks/#{id}"
  defp item_href(%{type: :deal}), do: ~p"/deals"

  defp queue_icon_class(:danger), do: "bg-error/10 text-error"
  defp queue_icon_class(:warning), do: "bg-warning/10 text-warning"
  defp queue_icon_class(_tone), do: "bg-info/10 text-info"

  defp money_positive?(%Decimal{} = value), do: Decimal.compare(value, Decimal.new(0)) == :gt
  defp money_positive?(_value), do: false

  defp action_label(:reply), do: gettext("Reply")
  defp action_label(:complete), do: gettext("Complete")
  defp action_label(:review), do: gettext("Review")
  defp action_label(:set_next_action), do: gettext("Set next action")
  defp action_label(_action), do: gettext("Open")

  defp format_money(%Decimal{} = value) do
    rounded = Decimal.round(value, 0)
    "€#{Decimal.to_string(rounded, :normal)}"
  end

  defp format_money(_value), do: "€0"
end
