defmodule KonevoWeb.DealsLive.Index do
  use KonevoWeb, :live_view

  alias Konevo.Deals
  alias Konevo.Deals.Deal
  alias KonevoWeb.DealsLive.{Components, FormComponent}

  @all_sources ~w(email form referral import manual api)
  @value_slider_max 100_000
  @value_slider_step 1_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Deals"))
     |> assign(:search, "")
     |> assign(:archive_filter, :active)
     |> assign(:stage_ids, [])
     |> assign(:min_value, 0)
     |> assign(:min_probability, 0)
     |> assign(:close_from, "")
     |> assign(:close_to, "")
     |> assign(:sources, [])
     |> assign(:stages, [])
     |> assign(:stages_with_deals, [])
     |> assign(:deal, nil)
     |> assign(:pipeline_total, Decimal.new(0))
     |> assign(:pipeline_count, 0)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_filter_params(params)
      |> load_board()
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  defp apply_filter_params(socket, params) do
    filters = parse_filter_params(params)

    assign(socket, filters)
  end

  defp parse_filter_params(params) do
    %{
      search: Map.get(params, "search", ""),
      archive_filter: parse_archive_filter(Map.get(params, "archived", "")),
      stage_ids: parse_ids(Map.get(params, "stage_ids", "")),
      min_value: parse_slider(Map.get(params, "min_value", ""), 0, @value_slider_max),
      min_probability: parse_slider(Map.get(params, "min_probability", ""), 0, 100),
      close_from: parse_date_param(Map.get(params, "close_from", "")),
      close_to: parse_date_param(Map.get(params, "close_to", "")),
      sources: parse_sources(Map.get(params, "sources", ""))
    }
  end

  defp parse_ids(""), do: []

  defp parse_ids(str) when is_binary(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn s ->
      case Integer.parse(s) do
        {id, ""} when id > 0 -> [id]
        _ -> []
      end
    end)
  end

  defp parse_slider(str, min, max) when is_binary(str) and str != "" do
    case Integer.parse(str) do
      {n, ""} when n >= min and n <= max -> n
      _ -> min
    end
  end

  defp parse_slider(_, min, _max), do: min

  defp parse_date_param(str) when is_binary(str) and str != "" do
    case Date.from_iso8601(str) do
      {:ok, _} -> str
      _ -> ""
    end
  end

  defp parse_date_param(_), do: ""

  defp parse_archive_filter("archived"), do: :archived
  defp parse_archive_filter("all"), do: :all
  defp parse_archive_filter(_), do: :active

  defp parse_sources(""), do: []

  defp parse_sources(str) when is_binary(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.filter(&(&1 in @all_sources))
  end

  defp requested_source(source) when source in @all_sources, do: source
  defp requested_source(_source), do: nil

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp parse_id(_value), do: nil

  defp apply_action(socket, :index, _params) do
    assign(socket, :deal, nil)
  end

  defp apply_action(socket, :new, params) do
    scope = socket.assigns.current_scope
    stages = socket.assigns.stages

    default_stage_id =
      requested_stage_id(params["stage_id"], stages) || first_stage_id(stages)

    deal = %Deal{
      organization_id: scope.org.id,
      owner_id: scope.user.id,
      stage_id: default_stage_id,
      currency: "EUR",
      title: Map.get(params, "title"),
      source: requested_source(params["source"]),
      contact_id: parse_id(params["contact_id"])
    }

    assign(socket, :deal, deal)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope

    assign(socket, :deal, Deals.get_deal_by_slug_or_id!(scope, id))
  end

  defp requested_stage_id(nil, _stages), do: nil

  defp requested_stage_id(id, stages) do
    with {stage_id, ""} <- Integer.parse(to_string(id)),
         true <- Enum.any?(stages, &(&1.id == stage_id)) do
      stage_id
    else
      _ -> nil
    end
  end

  defp first_stage_id([stage | _]), do: stage.id
  defp first_stage_id([]), do: nil

  @impl true
  def handle_info({:saved, _deal}, socket) do
    {:noreply, load_board(socket)}
  end

  @impl true
  def handle_event("reposition-kanban", params, socket) do
    %{"id" => deal_id_str, "to" => %{"status" => to_stage_str}} = params
    scope = socket.assigns.current_scope

    with {deal_id, _} <- Integer.parse(deal_id_str),
         {stage_id, _} <- Integer.parse(to_stage_str),
         {:ok, _deal} <- Deals.move_deal_to_stage(scope, deal_id, stage_id) do
      {:noreply,
       socket
       |> put_flash(:success, gettext("Deal moved"))
       |> load_board()}
    else
      :error ->
        {:noreply, put_flash(socket, :error, gettext("Invalid request"))}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Could not move deal"))
         |> load_board()}
    end
  end

  @impl true
  def handle_event("delete_deal", %{"id" => id_str}, socket) do
    scope = socket.assigns.current_scope

    with {deal_id, _} <- Integer.parse(id_str),
         deal <- Deals.get_deal!(scope, deal_id),
         {:ok, _} <- Deals.delete_deal(scope, deal) do
      {:noreply,
       socket
       |> put_flash(:success, gettext("Deal deleted successfully"))
       |> load_board()}
    else
      :error ->
        {:noreply, put_flash(socket, :error, gettext("Invalid request"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete deal"))}
    end
  end

  def handle_event("archive_deal", %{"id" => id_str}, socket) do
    scope = socket.assigns.current_scope

    with {deal_id, _} <- Integer.parse(id_str),
         deal <- Deals.get_deal!(scope, deal_id),
         {:ok, _} <- Deals.archive_deal(scope, deal) do
      {:noreply,
       socket
       |> put_flash(:success, gettext("Deal archived"))
       |> load_board()}
    else
      :error ->
        {:noreply, put_flash(socket, :error, gettext("Invalid request"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not archive deal"))}
    end
  end

  def handle_event("restore_deal", %{"id" => id_str}, socket) do
    scope = socket.assigns.current_scope

    with {deal_id, _} <- Integer.parse(id_str),
         deal <- Deals.get_deal!(scope, deal_id),
         {:ok, _} <- Deals.restore_deal(scope, deal) do
      {:noreply,
       socket
       |> put_flash(:success, gettext("Deal restored"))
       |> load_board()}
    else
      :error ->
        {:noreply, put_flash(socket, :error, gettext("Invalid request"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not restore deal"))}
    end
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: build_url(socket, %{search: q}), replace: true)}
  end

  def handle_event("clear_search", _, socket) do
    {:noreply, push_patch(socket, to: build_url(socket, %{search: ""}), replace: true)}
  end

  def handle_event("set_archive_filter", %{"filter" => filter}, socket) do
    archive_filter = parse_archive_filter(filter)
    {:noreply, push_patch(socket, to: build_url(socket, %{archive_filter: archive_filter}))}
  end

  def handle_event("toggle_stage", %{"id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} ->
        stage_ids = toggle_list_value(socket.assigns.stage_ids, id)
        {:noreply, push_patch(socket, to: build_url(socket, %{stage_ids: stage_ids}))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("filter_value", %{"min_value" => min_value}, socket) do
    value = parse_slider(min_value, 0, @value_slider_max)
    {:noreply, push_patch(socket, to: build_url(socket, %{min_value: value}))}
  end

  def handle_event("filter_probability", %{"min_probability" => min_probability}, socket) do
    probability = parse_slider(min_probability, 0, 100)
    {:noreply, push_patch(socket, to: build_url(socket, %{min_probability: probability}))}
  end

  def handle_event("filter_date_range", %{"from" => from, "to" => to}, socket) do
    from = parse_date_param(from)
    to = parse_date_param(to)

    {:noreply, push_patch(socket, to: build_url(socket, %{close_from: from, close_to: to}))}
  end

  def handle_event("toggle_source", %{"source" => source}, socket) do
    if source in @all_sources do
      sources = toggle_list_value(socket.assigns.sources, source)
      {:noreply, push_patch(socket, to: build_url(socket, %{sources: sources}))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_all_sources", _, socket) do
    sources =
      if length(socket.assigns.sources) == length(@all_sources),
        do: [],
        else: @all_sources

    {:noreply, push_patch(socket, to: build_url(socket, %{sources: sources}))}
  end

  def handle_event("clear_filters", _, socket) do
    socket =
      socket
      |> push_patch(
        to:
          build_url(socket, %{
            search: "",
            archive_filter: :active,
            stage_ids: [],
            min_value: 0,
            min_probability: 0,
            close_from: "",
            close_to: "",
            sources: []
          })
      )
      |> push_event("date_range:clear", %{})

    {:noreply, socket}
  end

  defp load_board(socket) do
    scope = socket.assigns.current_scope
    stages = Deals.list_stages(scope)

    deals =
      Deals.list_deals(scope,
        search: socket.assigns.search,
        archive_filter: socket.assigns.archive_filter,
        stage_ids: socket.assigns.stage_ids,
        min_value: min_value_filter(socket.assigns.min_value),
        min_probability: min_probability_filter(socket.assigns.min_probability),
        close_from: date_filter(socket.assigns.close_from),
        close_to: date_filter(socket.assigns.close_to),
        sources: socket.assigns.sources,
        sort_by: :inserted_at,
        sort_dir: :asc
      )

    deals_by_stage = Enum.group_by(deals, & &1.stage_id)
    visible_stages = visible_stages(stages, socket.assigns.stage_ids)

    stages_with_deals =
      Enum.map(visible_stages, fn stage ->
        {stage, Map.get(deals_by_stage, stage.id, [])}
      end)

    pipeline_total =
      Enum.reduce(deals, Decimal.new(0), fn deal, acc ->
        if deal.value, do: Decimal.add(acc, deal.value), else: acc
      end)

    socket
    |> assign(:stages, stages)
    |> assign(:stages_with_deals, stages_with_deals)
    |> assign(:pipeline_count, length(deals))
    |> assign(:pipeline_total, pipeline_total)
  end

  defp visible_stages(stages, []), do: stages

  defp visible_stages(stages, stage_ids) do
    Enum.filter(stages, &(&1.id in stage_ids))
  end

  defp min_value_filter(value) when is_integer(value) and value > 0, do: Decimal.new(value)
  defp min_value_filter(_), do: nil

  defp min_probability_filter(value) when is_integer(value) and value > 0, do: value
  defp min_probability_filter(_), do: nil

  defp date_filter(""), do: nil

  defp date_filter(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp toggle_list_value(values, value) do
    if value in values, do: List.delete(values, value), else: [value | values]
  end

  defp build_url(socket, overrides) do
    search = Map.get(overrides, :search, socket.assigns.search)
    archive_filter = Map.get(overrides, :archive_filter, socket.assigns.archive_filter)
    stage_ids = Map.get(overrides, :stage_ids, socket.assigns.stage_ids)
    min_value = Map.get(overrides, :min_value, socket.assigns.min_value)
    min_probability = Map.get(overrides, :min_probability, socket.assigns.min_probability)
    close_from = Map.get(overrides, :close_from, socket.assigns.close_from)
    close_to = Map.get(overrides, :close_to, socket.assigns.close_to)
    sources = Map.get(overrides, :sources, socket.assigns.sources)

    params =
      []
      |> push_param("search", search, "")
      |> push_param("archived", archive_filter_param(archive_filter), "active")
      |> push_param("stage_ids", Enum.join(stage_ids, ","), "")
      |> push_param("min_value", to_string(min_value), "0")
      |> push_param("min_probability", to_string(min_probability), "0")
      |> push_param("close_from", close_from, "")
      |> push_param("close_to", close_to, "")
      |> push_param("sources", Enum.join(sources, ","), "")
      |> Map.new()

    if map_size(params) == 0, do: ~p"/deals", else: ~p"/deals?#{params}"
  end

  defp push_param(list, _key, default, default), do: list
  defp push_param(list, key, value, _default), do: [{key, value} | list]

  defp archive_filter_param(:archived), do: "archived"
  defp archive_filter_param(:all), do: "all"
  defp archive_filter_param(_), do: "active"

  defp archive_filter_options do
    [
      {gettext("Active"), "active", "icon-[tabler--circle-check]"},
      {gettext("Archived"), "archived", "icon-[tabler--archive]"},
      {gettext("All"), "all", "icon-[tabler--stack-2]"}
    ]
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:all_sources, @all_sources)
      |> assign(:value_slider_max, @value_slider_max)
      |> assign(:value_slider_step, @value_slider_step)
      |> assign(
        :filters_active?,
        assigns.search != "" or assigns.stage_ids != [] or assigns.min_value > 0 or
          assigns.min_probability > 0 or assigns.close_from != "" or assigns.close_to != "" or
          assigns.sources != [] or assigns.archive_filter != :active
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.page title={@page_title}>
        <:actions>
          <.button
            patch={~p"/deals/new"}
            id="new-deal-button"
            class="btn btn-primary btn-sm gap-1.5"
          >
            <.icon name="icon-[tabler--plus]" class="size-4" /> {gettext("Add deal")}
          </.button>
        </:actions>

        <%!-- Toolbar --%>
        <div class="mb-4 flex flex-wrap items-center gap-2">
          <%!-- Search --%>
          <div class="relative w-56 shrink-0">
            <.icon
              name="icon-[tabler--search]"
              class="pointer-events-none absolute left-2.5 top-1/2 z-10 size-3.5 -translate-y-1/2 text-base-content/40"
            />
            <form phx-change="search" phx-submit="search" id="deal-search-form">
              <input
                type="text"
                name="q"
                value={@search}
                placeholder={gettext("Search deals, contacts")}
                phx-debounce="300"
                class={[
                  "input input-sm input-bordered w-full pl-8 pr-8 transition-colors",
                  @search != "" && "border-primary/60"
                ]}
                autocomplete="off"
              />
            </form>
            <button
              :if={@search != ""}
              phx-click="clear_search"
              type="button"
              aria-label={gettext("Clear search")}
              class="absolute right-2.5 top-1/2 -translate-y-1/2 text-base-content/40 transition-colors hover:text-base-content"
            >
              <.icon name="icon-[tabler--x]" class="size-3.5" />
            </button>
          </div>

          <.archive_filter_dropdown
            id="deals-archive-filter"
            selected={@archive_filter}
            options={archive_filter_options()}
          />

          <%!-- Filter dropdowns --%>
          <%!-- Mobile filter toggle --%>
          <button
            type="button"
            class={[
              "btn btn-sm gap-1.5 border select-none sm:hidden",
              if(@filters_active?,
                do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                else:
                  "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
              )
            ]}
            phx-click={
              JS.toggle(
                to: "#deals-filter-panel",
                display: "flex",
                in:
                  {"transition ease-out duration-200", "opacity-0 -translate-y-1",
                   "opacity-100 translate-y-0"},
                out:
                  {"transition ease-in duration-150", "opacity-100 translate-y-0",
                   "opacity-0 -translate-y-1"}
              )
              |> JS.toggle_class("rotate-180", to: "#deals-filter-chevron")
            }
          >
            <span class="icon-[tabler--adjustments-horizontal] size-3.5" />
            {gettext("Filters")}
            <span
              :if={@filters_active?}
              class="size-2 rounded-full bg-primary"
            />
            <span
              id="deals-filter-chevron"
              class="icon-[tabler--chevron-down] size-3.5 opacity-50 transition-transform duration-200"
            />
          </button>
          <div
            id="deals-filter-panel"
            class="hidden flex-wrap items-center gap-2 sm:flex"
          >
            <%!-- Stage filter --%>
            <div class="relative" id="deal-stage-filter-dropdown" phx-hook="FilterPanel">
              <button
                type="button"
                data-toggle
                class={[
                  "btn btn-sm gap-1.5 border select-none transition-all",
                  if(@stage_ids != [],
                    do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                    else:
                      "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                  )
                ]}
              >
                <.icon name="icon-[tabler--layout-kanban]" class="size-3.5" />
                {gettext("Stage")}
                <span
                  :if={@stage_ids != []}
                  class="flex size-4 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-content"
                >
                  {length(@stage_ids)}
                </span>
                <.icon name="icon-[tabler--chevron-down]" class="size-3.5 opacity-50" />
              </button>

              <div
                data-panel
                class="row-menu-closed z-30 max-h-72 w-56 overflow-y-auto overflow-x-hidden rounded-xl border border-base-content/20 bg-base-100 p-1 shadow-xl"
              >
                <label
                  :for={stage <- @stages}
                  class="flex w-full cursor-pointer select-none items-center gap-3 rounded-lg px-3 py-2 transition-colors hover:bg-base-200"
                >
                  <input
                    type="checkbox"
                    class="checkbox checkbox-xs checkbox-primary shrink-0"
                    checked={stage.id in @stage_ids}
                    phx-click="toggle_stage"
                    phx-value-id={stage.id}
                  />
                  <span
                    class="size-2 rounded-full shrink-0"
                    style={"background-color: #{stage_color(stage.color)}"}
                  />
                  <span class="truncate text-sm">{stage.name}</span>
                </label>
              </div>
            </div>

            <%!-- Value filter --%>
            <div class="relative" id="deal-value-filter-dropdown" phx-hook="FilterPanel">
              <button
                type="button"
                data-toggle
                class={[
                  "btn btn-sm gap-1.5 border select-none transition-all",
                  if(@min_value > 0,
                    do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                    else:
                      "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                  )
                ]}
              >
                <.icon name="icon-[tabler--cash]" class="size-3.5" />
                {gettext("Value")}
                <span
                  :if={@min_value > 0}
                  class="rounded-full bg-primary px-1.5 py-0.5 text-[10px] font-bold text-primary-content"
                >
                  {format_slider_value(@min_value)}
                </span>
                <.icon name="icon-[tabler--chevron-down]" class="size-3.5 opacity-50" />
              </button>

              <div
                data-panel
                class="row-menu-closed z-30 w-72 overflow-hidden rounded-xl border border-base-content/20 bg-base-100 p-4 shadow-xl"
              >
                <form
                  phx-change="filter_value"
                  phx-submit="filter_value"
                  id="deal-value-filter-form"
                >
                  <.input
                    type="range"
                    id="deal-min-value"
                    name="min_value"
                    label={gettext("Minimum deal value")}
                    value={@min_value}
                    min="0"
                    max={@value_slider_max}
                    step={@value_slider_step}
                    suffix=" EUR"
                    class="range range-primary w-full"
                  />
                </form>
              </div>
            </div>

            <%!-- Probability filter --%>
            <div class="relative" id="deal-probability-filter-dropdown" phx-hook="FilterPanel">
              <button
                type="button"
                data-toggle
                class={[
                  "btn btn-sm gap-1.5 border select-none transition-all",
                  if(@min_probability > 0,
                    do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                    else:
                      "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                  )
                ]}
              >
                <.icon name="icon-[tabler--percentage]" class="size-3.5" />
                {gettext("Win probability")}
                <span
                  :if={@min_probability > 0}
                  class="rounded-full bg-primary px-1.5 py-0.5 text-[10px] font-bold text-primary-content"
                >
                  {@min_probability}%
                </span>
                <.icon name="icon-[tabler--chevron-down]" class="size-3.5 opacity-50" />
              </button>

              <div
                data-panel
                class="row-menu-closed z-30 w-72 overflow-hidden rounded-xl border border-base-content/20 bg-base-100 p-4 shadow-xl"
              >
                <form
                  phx-change="filter_probability"
                  phx-submit="filter_probability"
                  id="deal-probability-filter-form"
                >
                  <.input
                    type="range"
                    id="deal-min-probability"
                    name="min_probability"
                    label={gettext("Minimum win probability")}
                    value={@min_probability}
                    min="0"
                    max="100"
                    step="5"
                    suffix="%"
                    class="range range-primary w-full"
                  />
                </form>
              </div>
            </div>

            <%!-- Close date range --%>
            <.date_range_picker
              id="deal-close-date-filter"
              created_from={@close_from}
              created_to={@close_to}
              empty_label={gettext("Close date")}
            />

            <%!-- Source filter --%>
            <div class="relative" id="deal-source-filter-dropdown" phx-hook="FilterPanel">
              <button
                type="button"
                data-toggle
                class={[
                  "btn btn-sm gap-1.5 border select-none transition-all",
                  if(@sources != [],
                    do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                    else:
                      "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                  )
                ]}
              >
                <.icon name="icon-[tabler--tag]" class="size-3.5" />
                {gettext("Source")}
                <span
                  :if={@sources != []}
                  class="flex size-4 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-content"
                >
                  {length(@sources)}
                </span>
                <.icon name="icon-[tabler--chevron-down]" class="size-3.5 opacity-50" />
              </button>

              <div
                data-panel
                class="row-menu-closed z-30 min-w-52 overflow-hidden rounded-xl border border-base-content/20 bg-base-100 shadow-xl"
              >
                <label class="flex w-full cursor-pointer select-none items-center gap-3 px-3 py-2.5 transition-colors hover:bg-base-200">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-xs checkbox-primary shrink-0"
                    checked={length(@sources) == length(@all_sources)}
                    phx-click="toggle_all_sources"
                    data-select-all
                  />
                  <span class="text-sm font-semibold">{gettext("Select all")}</span>
                </label>
                <div class="mx-2 border-t border-base-content/10" />
                <div class="p-1">
                  <label
                    :for={source <- @all_sources}
                    class="flex w-full cursor-pointer select-none items-center gap-3 rounded-lg px-3 py-2 transition-colors hover:bg-base-200"
                  >
                    <input
                      type="checkbox"
                      class="checkbox checkbox-xs checkbox-primary shrink-0"
                      checked={source in @sources}
                      phx-click="toggle_source"
                      phx-value-source={source}
                      data-select-option
                    />
                    <.icon
                      name={source_icon(source)}
                      class="size-4 shrink-0 text-base-content/50"
                    />
                    <span class="truncate text-sm">{source_label(source)}</span>
                  </label>
                </div>
              </div>
            </div>

            <%!-- Clear all filters --%>
            <button
              :if={@filters_active?}
              phx-click="clear_filters"
              type="button"
              class="btn btn-sm gap-1.5 border border-base-content/20 bg-base-100 text-base-content/60 transition-all hover:border-base-content/30 hover:text-base-content"
            >
              <.icon name="icon-[tabler--x]" class="size-3" />
              {gettext("Clear filters")}
            </button>
          </div>

          <div class="ml-auto flex flex-wrap items-center gap-2">
            <span class="badge badge-sm border border-base-content/20 bg-base-100 text-base-content/60 font-medium">
              {@pipeline_count} {gettext("deals")}
            </span>
            <span
              :if={!Decimal.equal?(@pipeline_total, 0)}
              class="badge badge-sm border border-success/30 bg-success/10 text-success font-semibold"
            >
              {format_pipeline_total(@pipeline_total)}
            </span>
          </div>
        </div>

        <%!-- Kanban shell --%>
        <div class="flex h-[calc(100vh-13rem)] min-h-120 flex-col overflow-hidden">
          <%!-- Board area --%>
          <div class="flex-1 overflow-hidden">
            <%!-- Mobile stacked view --%>
            <div class="md:hidden h-full overflow-y-auto space-y-3">
              <%!-- Empty state --%>
              <div
                :if={@stages == []}
                class="mt-2 flex min-h-56 flex-col items-center justify-center rounded-xl border border-base-content/20 bg-base-100 px-6 py-12 text-center shadow-sm shadow-base-content/5"
              >
                <div class="mb-4 flex size-16 items-center justify-center rounded-2xl bg-base-100">
                  <.icon name="icon-[tabler--layout-kanban]" class="size-8 text-base-content/30" />
                </div>
                <h3 class="mb-1 text-base font-semibold text-base-content">
                  {gettext("No pipeline stages")}
                </h3>
                <p class="text-sm text-base-content/50">
                  {gettext("Configure deal stages in Settings to get started.")}
                </p>
              </div>

              <%= for {stage, deals} <- @stages_with_deals do %>
                <div class="rounded-xl border border-base-content/10 overflow-hidden bg-base-100 shadow-sm">
                  <button
                    id={"mobile-stage-toggle-#{stage.id}"}
                    phx-click={toggle_mobile_js(stage.id)}
                    class="relative w-full flex items-center justify-between px-4 py-3 text-left"
                  >
                    <div
                      class="absolute inset-0"
                      style={"background-color: #{stage_color(stage.color)}; opacity: 0.07;"}
                    />
                    <div
                      class="absolute bottom-0 left-0 right-0 h-0.5"
                      style={"background-color: #{stage_color(stage.color)}"}
                    />
                    <div class="relative flex items-center gap-2 min-w-0">
                      <div
                        class="size-2.5 rounded-full shrink-0"
                        style={"background-color: #{stage_color(stage.color)}"}
                      />
                      <span class="text-sm font-semibold text-base-content truncate">
                        {stage.name}
                      </span>
                      <span
                        class="badge badge-sm font-semibold"
                        style={stage_count_style(stage.color)}
                      >
                        {length(deals)}
                      </span>
                    </div>
                    <span
                      id={"mobile-chevron-#{stage.id}"}
                      class="relative icon-[tabler--chevron-down] size-4 text-base-content/40 transition-transform duration-200 shrink-0"
                    />
                  </button>
                  <div
                    id={"mobile-stage-body-#{stage.id}"}
                    class="hidden space-y-2 p-3 bg-base-200/30 border-t border-base-content/10"
                  >
                    <div
                      :if={deals == []}
                      class="text-center py-4 text-xs text-base-content/40 italic"
                    >
                      {gettext("No deals in this stage")}
                    </div>
                    <%= for deal <- deals do %>
                      <Components.deal_card id={"m-deal-#{deal.id}"} deal={deal} />
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
            <%!-- Desktop kanban: horizontal scroll --%>
            <div class="hidden md:block h-full overflow-x-auto overflow-y-hidden">
              <div class={[
                "h-full gap-2 pb-2",
                if(@stages == [],
                  do: "flex w-full items-start justify-center pt-4",
                  else: "inline-flex"
                )
              ]}>
                <%!-- Empty state --%>
                <div
                  :if={@stages == []}
                  class="flex min-h-64 w-full flex-col items-center justify-center rounded-xl border border-base-content/20 bg-base-100 px-6 py-14 text-center shadow-sm shadow-base-content/5"
                >
                  <div class="mb-4 flex size-16 items-center justify-center rounded-2xl bg-base-100">
                    <.icon name="icon-[tabler--layout-kanban]" class="size-8 text-base-content/30" />
                  </div>

                  <h3 class="mb-1 text-base font-semibold text-base-content">
                    {gettext("No pipeline stages")}
                  </h3>

                  <p class="text-sm text-base-content/50">
                    {gettext("Configure deal stages in Settings to get started.")}
                  </p>
                </div>
                <%!-- Stage columns --%>
                <%= for {stage, deals} <- @stages_with_deals do %>
                  <div id={"kc-#{stage.id}"} class="relative shrink-0 flex flex-row h-full pr-2">
                    <%!-- Full expanded column --%>
                    <div
                      id={"kc-full-#{stage.id}"}
                      class="kc-panel relative flex flex-col w-60 h-full rounded-xl border border-base-content/20 shadow-sm bg-base-100"
                    >
                      <Components.stage_column_header stage={stage} deals={deals} />
                      <div
                        id={"kanban-col-#{stage.id}"}
                        phx-hook="SortableKanban"
                        data-group="kanban-groups"
                        data-status={stage.id}
                        class={[
                          "relative flex-1 min-h-16 space-y-2 overflow-y-auto p-3 bg-base-200/30",
                          "transition-colors duration-150"
                        ]}
                      >
                        <div
                          :if={deals == []}
                          id={"kanban-col-#{stage.id}-empty"}
                          class="pointer-events-none absolute left-3 right-3 top-3 z-0 flex h-24 items-center justify-center rounded-lg border-2 border-dashed border-base-content/10 text-xs text-base-content/30 select-none"
                        >
                          {gettext("Drop deals here")}
                        </div>

                        <%= for deal <- deals do %>
                          <Components.deal_card id={"deal-#{deal.id}"} deal={deal} />
                        <% end %>
                      </div>
                    </div>
                    <button
                      id={"stage-collapse-#{stage.id}"}
                      phx-click={collapse_js(stage.id)}
                      type="button"
                      class={[
                        "absolute left-60 top-1/2 z-30 flex size-7 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border border-base-content/20",
                        "bg-base-100 text-base-content/70 shadow-lg shadow-base-content/15 transition-all",
                        "hover:scale-105 hover:border-primary/30 hover:bg-primary/10 hover:text-primary"
                      ]}
                      title={gettext("Collapse column")}
                      aria-label={gettext("Collapse column")}
                    >
                      <.icon name="icon-[tabler--chevron-left]" class="size-4" />
                    </button>
                    <%!-- Collapsed strip (hidden by default) --%>
                    <div
                      id={"kc-strip-#{stage.id}"}
                      class="kc-panel kc-panel-collapsed flex flex-col w-10 h-full rounded-xl border border-base-content/10 shadow-sm bg-base-100"
                    >
                      <Components.stage_column_strip
                        stage={stage}
                        deals={deals}
                        on_expand={expand_js(stage.id)}
                      />
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </Layouts.page>

      <%!-- New / Edit modal --%>
      <.modal
        :if={@live_action in [:new, :edit]}
        id="deal-modal"
        show
        on_cancel={JS.patch(~p"/deals")}
      >
        <.live_component
          module={FormComponent}
          id={if @deal && @deal.id, do: "deal-form-#{@deal.id}", else: "deal-form-new"}
          action={@live_action}
          title={if @live_action == :new, do: gettext("New deal"), else: gettext("Edit deal")}
          deal={@deal}
          current_scope={@current_scope}
          patch={~p"/deals"}
        />
      </.modal>
    </Layouts.app>
    """
  end

  defp collapse_js(stage_id) do
    JS.add_class("kc-panel-collapsed", to: "#kc-full-#{stage_id}")
    |> JS.remove_class("kc-panel-collapsed", to: "#kc-strip-#{stage_id}")
    |> JS.add_class("hidden", to: "#stage-collapse-#{stage_id}")
  end

  defp expand_js(stage_id) do
    JS.remove_class("kc-panel-collapsed", to: "#kc-full-#{stage_id}")
    |> JS.add_class("kc-panel-collapsed", to: "#kc-strip-#{stage_id}")
    |> JS.remove_class("hidden", to: "#stage-collapse-#{stage_id}")
  end

  defp toggle_mobile_js(stage_id) do
    JS.toggle(
      to: "#mobile-stage-body-#{stage_id}",
      in:
        {"transition-all duration-200 ease-out", "opacity-0 -translate-y-1",
         "opacity-100 translate-y-0"},
      out:
        {"transition-all duration-150 ease-in", "opacity-100 translate-y-0",
         "opacity-0 -translate-y-1"}
    )
    |> JS.toggle_class("rotate-180", to: "#mobile-chevron-#{stage_id}")
  end

  defp format_pipeline_total(total) do
    num =
      total
      |> Decimal.round(0)
      |> Decimal.to_integer()
      |> abs()
      |> Integer.to_string()
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    "#{num} EUR"
  end

  defp format_slider_value(value) when value >= 1000 do
    "#{div(value, 1000)}k"
  end

  defp format_slider_value(value), do: Integer.to_string(value)

  defp source_label("email"), do: gettext("Email")
  defp source_label("form"), do: gettext("Form")
  defp source_label("referral"), do: gettext("Referral")
  defp source_label("import"), do: gettext("Import")
  defp source_label("manual"), do: gettext("Manual")
  defp source_label("api"), do: gettext("API")
  defp source_label(source), do: source

  defp source_icon("email"), do: "icon-[tabler--mail]"
  defp source_icon("form"), do: "icon-[tabler--forms]"
  defp source_icon("referral"), do: "icon-[tabler--user-share]"
  defp source_icon("import"), do: "icon-[tabler--file-import]"
  defp source_icon("manual"), do: "icon-[tabler--hand-click]"
  defp source_icon("api"), do: "icon-[tabler--api]"
  defp source_icon(_source), do: "icon-[tabler--tag]"

  defp stage_color(nil), do: "#9ca3af"
  defp stage_color("#6b7280"), do: "#4b5563"
  defp stage_color("#6B7280"), do: "#4b5563"
  defp stage_color(color), do: color

  defp stage_count_style(color) do
    color = stage_color(color)

    "color: #{color}; " <>
      "border-color: color-mix(in srgb, #{color} 28%, transparent); " <>
      "background-color: color-mix(in srgb, #{color} 14%, var(--color-base-100));"
  end
end
