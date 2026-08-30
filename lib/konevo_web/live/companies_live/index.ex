defmodule KonevoWeb.CompaniesLive.Index do
  use KonevoWeb, :live_view

  alias Konevo.Companies
  alias Konevo.Companies.Company

  @per_page 25
  @sortable_columns ~w(name industry contacts inserted_at)

  @impl true
  def mount(_params, _session, socket) do
    view_mode =
      case get_connect_params(socket) do
        %{"viewport" => "mobile"} -> :card
        _ -> :table
      end

    {:ok,
     socket
     |> assign(:page_title, gettext("Companies"))
     |> assign(:view_mode, view_mode)
     |> assign(:search, "")
     |> assign(:archive_filter, :active)
     |> assign(:industries_filter, [])
     |> assign(:all_industries, [])
     |> assign(:created_from, "")
     |> assign(:created_to, "")
     |> assign(:sort_by, :name)
     |> assign(:sort_dir, :asc)
     |> assign(:page, 1)
     |> assign(:total, 0)
     |> assign(:companies_request_ref, nil)
     |> assign(:company, nil)
     |> stream(:companies, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket = apply_action(socket, socket.assigns.live_action, params)
    socket = load_companies(socket, params)

    {:noreply, assign(socket, :return_to, build_url(socket, %{}))}
  end

  defp load_companies(socket, params) do
    filters = parse_params(params)
    scope = socket.assigns.current_scope
    caller = self()
    request_ref = make_ref()

    socket
    |> assign(
      Map.take(filters, [
        :search,
        :archive_filter,
        :industries_filter,
        :created_from,
        :created_to,
        :sort_by,
        :sort_dir,
        :page
      ])
    )
    |> assign(
      :all_industries,
      Companies.list_industries(scope, archive_filter: filters.archive_filter)
    )
    |> assign(:companies_request_ref, request_ref)
    |> cancel_async(:companies)
    |> stream_async(:companies, fn ->
      {companies, total} =
        Companies.list_companies(scope,
          search: filters.search,
          archive_filter: filters.archive_filter,
          industries: filters.industries_filter,
          created_from: filters.created_from,
          created_to: filters.created_to,
          sort_by: filters.sort_by,
          sort_dir: filters.sort_dir,
          page: filters.page,
          per_page: @per_page
        )

      send(caller, {:companies_total, request_ref, total})
      {:ok, companies, reset: true}
    end)
  end

  defp parse_params(params) do
    %{
      search: Map.get(params, "search", ""),
      archive_filter: parse_archive_filter(Map.get(params, "archived", "")),
      industries_filter: parse_industries_filter(Map.get(params, "industries_filter", "")),
      created_from: parse_date(Map.get(params, "created_from", "")),
      created_to: parse_date(Map.get(params, "created_to", "")),
      sort_by: parse_sort_by(Map.get(params, "sort_by", "")),
      sort_dir: if(Map.get(params, "sort_dir") == "desc", do: :desc, else: :asc),
      page: parse_page(Map.get(params, "page", ""))
    }
  end

  defp parse_industries_filter(""), do: []

  defp parse_industries_filter(str) when is_binary(str) do
    str |> String.split(",", trim: true)
  end

  defp parse_sort_by(value) when value in @sortable_columns, do: String.to_existing_atom(value)
  defp parse_sort_by(_value), do: :name

  defp parse_page(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _other -> 1
    end
  end

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, _date} -> value
      {:error, _reason} -> ""
    end
  end

  defp parse_archive_filter("archived"), do: :archived
  defp parse_archive_filter("all"), do: :all
  defp parse_archive_filter(_), do: :active

  defp apply_action(socket, :edit, %{"id" => id}) do
    assign(
      socket,
      :company,
      Companies.get_company_by_slug_or_id!(socket.assigns.current_scope, id)
    )
  end

  defp apply_action(socket, :new, _params), do: assign(socket, :company, %Company{})
  defp apply_action(socket, :index, _params), do: assign(socket, :company, nil)

  @impl true
  def handle_info({:companies_total, request_ref, total}, socket) do
    if request_ref == socket.assigns.companies_request_ref do
      {:noreply, assign(socket, :total, total)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({KonevoWeb.CompaniesLive.FormComponent, {:saved, company, action}}, socket) do
    company = Companies.get_company!(socket.assigns.current_scope, company.id)

    {:noreply,
     socket
     |> put_flash(:success, saved_message(action))
     |> update(:total, fn total -> if action == :created, do: total + 1, else: total end)
     |> stream_insert(:companies, company)
     |> push_patch(to: socket.assigns.return_to)}
  end

  defp saved_message(:created), do: gettext("Company created")
  defp saved_message(:updated), do: gettext("Company updated")

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: build_url(socket, %{search: q, page: 1}), replace: true)}
  end

  def handle_event("clear_search", _, socket) do
    {:noreply, push_patch(socket, to: build_url(socket, %{search: "", page: 1}), replace: true)}
  end

  def handle_event("set_archive_filter", %{"filter" => filter}, socket) do
    archive_filter = parse_archive_filter(filter)

    {:noreply,
     push_patch(socket, to: build_url(socket, %{archive_filter: archive_filter, page: 1}))}
  end

  def handle_event("toggle_industry", %{"industry" => industry}, socket) do
    current = socket.assigns.industries_filter

    new_industries =
      if industry in current,
        do: List.delete(current, industry),
        else: [industry | current]

    {:noreply,
     push_patch(socket, to: build_url(socket, %{industries_filter: new_industries, page: 1}))}
  end

  def handle_event("filter_date_range", %{"from" => from, "to" => to}, socket) do
    from = parse_date(from)
    to = parse_date(to)

    {:noreply,
     push_patch(socket, to: build_url(socket, %{created_from: from, created_to: to, page: 1}))}
  end

  def handle_event("clear_filters", _, socket) do
    socket =
      socket
      |> push_patch(
        to:
          build_url(socket, %{
            search: "",
            archive_filter: :active,
            industries_filter: [],
            created_from: "",
            created_to: "",
            page: 1
          })
      )
      |> push_event("date_range:clear", %{})

    {:noreply, socket}
  end

  def handle_event("sort", %{"by" => by}, socket) do
    case Companies.authorize_companies(socket.assigns.current_scope, :read) do
      :ok ->
        sort_by = parse_sort_by(by)

        sort_dir =
          if socket.assigns.sort_by == sort_by and socket.assigns.sort_dir == :asc,
            do: :desc,
            else: :asc

        {:noreply,
         push_patch(socket,
           to: build_url(socket, %{sort_by: sort_by, sort_dir: sort_dir, page: 1})
         )}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Not allowed"))}
    end
  end

  def handle_event("page", %{"n" => value}, socket) do
    case Integer.parse(value) do
      {n, ""} when n > 0 ->
        {:noreply, push_patch(socket, to: build_url(socket, %{page: n}))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    view_mode = parse_view_mode(mode)

    {:noreply, assign(socket, :view_mode, view_mode)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    company = Companies.get_company!(socket.assigns.current_scope, id)

    case Companies.delete_company(socket.assigns.current_scope, company) do
      {:ok, deleted} ->
        {:noreply,
         socket
         |> update(:total, &max(&1 - 1, 0))
         |> stream_delete(:companies, deleted)
         |> put_flash(:success, gettext("Company deleted"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot delete this company"))}
    end
  end

  def handle_event("archive", %{"id" => id}, socket) do
    company = Companies.get_company!(socket.assigns.current_scope, id)

    case Companies.archive_company(socket.assigns.current_scope, company) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:success, gettext("Company archived"))
         |> apply_company_archive_change(company, updated)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot archive this company"))}
    end
  end

  def handle_event("restore", %{"id" => id}, socket) do
    company = Companies.get_company!(socket.assigns.current_scope, id)

    case Companies.restore_company(socket.assigns.current_scope, company) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:success, gettext("Company restored"))
         |> apply_company_archive_change(company, updated)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot restore this company"))}
    end
  end

  defp build_url(socket, overrides) do
    search = Map.get(overrides, :search, socket.assigns.search)
    archive_filter = Map.get(overrides, :archive_filter, socket.assigns.archive_filter)
    industries_filter = Map.get(overrides, :industries_filter, socket.assigns.industries_filter)
    created_from = Map.get(overrides, :created_from, socket.assigns.created_from)
    created_to = Map.get(overrides, :created_to, socket.assigns.created_to)
    sort_by = Map.get(overrides, :sort_by, socket.assigns.sort_by)
    sort_dir = Map.get(overrides, :sort_dir, socket.assigns.sort_dir)
    page = Map.get(overrides, :page, socket.assigns.page)

    params =
      []
      |> push_param("search", search, "")
      |> push_param("archived", archive_filter_param(archive_filter), "active")
      |> push_param("industries_filter", Enum.join(industries_filter, ","), "")
      |> push_param("created_from", created_from, "")
      |> push_param("created_to", created_to, "")
      |> push_param("sort_by", to_string(sort_by), "name")
      |> push_param("sort_dir", to_string(sort_dir), "asc")
      |> push_param("page", to_string(page), "1")
      |> Map.new()

    if map_size(params) == 0, do: ~p"/companies", else: ~p"/companies?#{params}"
  end

  defp edit_path(company, return_to) do
    case URI.parse(return_to).query do
      nil -> ~p"/companies/#{company}/edit/inline"
      query -> ~p"/companies/#{company}/edit/inline?#{URI.decode_query(query)}"
    end
  end

  defp show_path(company, return_to), do: ~p"/companies/#{company}?#{[return_to: return_to]}"

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

  defp apply_company_archive_change(socket, old_company, updated_company) do
    case socket.assigns.archive_filter do
      :all ->
        company = Companies.get_company!(socket.assigns.current_scope, updated_company.id)
        stream_insert(socket, :companies, company)

      _ ->
        socket
        |> update(:total, &max(&1 - 1, 0))
        |> stream_delete(:companies, old_company)
    end
  end

  defp total_pages(total), do: max(1, ceil(total / @per_page))

  defp page_display(_current, total_pages) when total_pages <= 7 do
    Enum.to_list(1..total_pages)
  end

  defp page_display(current, total_pages) do
    pages =
      [1, total_pages, max(2, current - 1), current, min(total_pages - 1, current + 1)]
      |> Enum.filter(&(&1 >= 1 and &1 <= total_pages))
      |> Enum.sort()
      |> Enum.uniq()

    Enum.reduce(tl(pages), [hd(pages)], fn n, acc ->
      if n - List.last(acc) > 1, do: acc ++ [:gap, n], else: acc ++ [n]
    end)
  end

  @impl true
  def render(assigns) do
    total_pages = total_pages(assigns.total)

    assigns =
      assigns
      |> assign(:total_pages, total_pages)
      |> assign(
        :page_from,
        if(assigns.total > 0, do: (assigns.page - 1) * @per_page + 1, else: 0)
      )
      |> assign(:page_to, min(assigns.page * @per_page, assigns.total))
      |> assign(:page_numbers, page_display(assigns.page, total_pages))
      |> assign(
        :filters_active?,
        assigns.search != "" or assigns.industries_filter != [] or
          assigns.created_from != "" or assigns.created_to != "" or
          assigns.archive_filter != :active
      )
      |> assign(
        :filter_controls_active?,
        assigns.industries_filter != [] or assigns.created_from != "" or
          assigns.created_to != "" or assigns.archive_filter != :active
      )
      |> assign(
        :filter_controls_count,
        length(assigns.industries_filter) +
          if(assigns.created_from != "", do: 1, else: 0) +
          if(assigns.created_to != "", do: 1, else: 0) +
          if(assigns.archive_filter != :active, do: 1, else: 0)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.page title={@page_title}>
        <:actions>
          <.button
            patch={~p"/companies/new"}
            id="new-company-button"
            class="btn btn-primary btn-sm gap-1.5"
          >
            <.icon name="icon-[tabler--plus]" class="size-4" /> {gettext("New Company")}
          </.button>
        </:actions>

        <%!-- Toolbar --%>
        <div class="mb-4 flex flex-wrap items-center gap-2">
          <%!-- Search --%>
          <div class="relative w-full shrink-0 sm:w-52">
            <span class="icon-[tabler--search] pointer-events-none absolute left-2.5 top-1/2 z-10 size-3.5 -translate-y-1/2 text-base-content/40" />
            <form phx-change="search" phx-submit="search" id="company-search-form">
              <input
                type="text"
                name="q"
                value={@search}
                placeholder={gettext("Search by name, website...")}
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
              <span class="icon-[tabler--x] size-3.5" />
            </button>
          </div>

          <div class="hidden sm:block">
            <.archive_filter_dropdown
              id="companies-archive-filter"
              selected={@archive_filter}
              options={archive_filter_options()}
            />
          </div>

          <div class="flex items-center gap-2 sm:hidden">
            <button
              type="button"
              class={[
                "btn btn-sm gap-1.5 border select-none",
                if(@filter_controls_active?,
                  do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                  else:
                    "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                )
              ]}
              phx-click={
                JS.toggle(
                  to: "#companies-filter-panel",
                  display: "flex",
                  in:
                    {"transition ease-out duration-200", "opacity-0 -translate-y-1",
                     "opacity-100 translate-y-0"},
                  out:
                    {"transition ease-in duration-150", "opacity-100 translate-y-0",
                     "opacity-0 -translate-y-1"}
                )
                |> JS.toggle_class("rotate-180", to: "#companies-filter-chevron")
              }
            >
              <span class="icon-[tabler--adjustments-horizontal] size-3.5" />
              {gettext("Filters")}
              <span
                :if={@filter_controls_active?}
                class="flex size-4 items-center justify-center rounded-full bg-primary text-[10px] font-bold text-primary-content"
              >
                {@filter_controls_count}
              </span>
              <span
                id="companies-filter-chevron"
                class="icon-[tabler--chevron-down] size-3.5 opacity-50 transition-transform duration-200"
              />
            </button>
            <button
              :if={@filter_controls_active?}
              id="companies-clear-filters-mobile"
              phx-click="clear_filters"
              type="button"
              aria-label={gettext("Clear filters")}
              class="btn btn-sm btn-square border border-base-content/20 bg-base-100 text-base-content/60 transition-all hover:border-base-content/30 hover:text-base-content"
            >
              <.icon name="icon-[tabler--x]" class="size-3.5" />
            </button>
          </div>

          <%!-- Filter dropdowns --%>
          <div
            id="companies-filter-panel"
            class="hidden w-full flex-wrap items-center gap-2 rounded-xl border border-secondary/35 bg-secondary/10 p-3 sm:w-auto sm:rounded-none sm:border-0 sm:bg-transparent sm:p-0 sm:flex"
          >
            <div class="sm:hidden">
              <.archive_filter_dropdown
                id="companies-archive-filter-mobile"
                selected={@archive_filter}
                options={archive_filter_options()}
              />
            </div>
            <%!-- Industry filter --%>
            <div
              :if={@all_industries != []}
              class="relative"
              id="industry-filter-dropdown"
              phx-hook="FilterPanel"
            >
              <button
                type="button"
                data-toggle
                class={[
                  "btn btn-sm gap-1.5 border select-none transition-all",
                  if(@industries_filter != [],
                    do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                    else:
                      "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                  )
                ]}
              >
                <span class="icon-[tabler--building] size-3.5" />
                {gettext("Industry")}
                <span
                  :if={@industries_filter != []}
                  class="flex size-4 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-content"
                >
                  {length(@industries_filter)}
                </span>
                <span class="icon-[tabler--chevron-down] size-3.5 opacity-50" />
              </button>

              <div
                data-panel
                class="row-menu-closed z-30 max-h-72 w-56 overflow-y-auto overflow-x-hidden rounded-xl border border-base-content/20 bg-base-100 p-1 shadow-xl"
              >
                <label
                  :for={industry <- @all_industries}
                  class="flex w-full cursor-pointer select-none items-center gap-3 rounded-lg px-3 py-2 transition-colors hover:bg-base-200"
                >
                  <input
                    type="checkbox"
                    class="checkbox checkbox-xs checkbox-primary shrink-0"
                    checked={industry in @industries_filter}
                    phx-click="toggle_industry"
                    phx-value-industry={industry}
                  />
                  <span class="truncate text-sm">{industry}</span>
                </label>
              </div>
            </div>

            <%!-- Date range filter --%>
            <.date_range_picker
              id="company-created-date-filter"
              created_from={@created_from}
              created_to={@created_to}
            />
            <div :if={@filters_active?} class="hidden border-l border-base-content/15 pl-2 sm:block">
              <button
                id="companies-clear-filters"
                phx-click="clear_filters"
                type="button"
                class="btn btn-sm gap-1.5 border border-base-content/20 bg-base-100 text-base-content/60 transition-all hover:border-base-content/30 hover:text-base-content"
              >
                <.icon name="icon-[tabler--x]" class="size-3" />
                {gettext("Clear filters")}
              </button>
            </div>
          </div>

          <%!-- View mode toggle --%>
          <div id="companies-toolbar-actions" class="ml-auto flex shrink-0 items-center gap-2">
            <div class="flex items-center gap-1 rounded-lg border border-base-content/15 bg-base-100 p-0.5 shadow-sm">
              <button
                id="companies-view-table"
                type="button"
                phx-click="set_view_mode"
                phx-value-mode="table"
                title={gettext("Table view")}
                class={[
                  "flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-medium transition-all",
                  if(@view_mode == :table,
                    do: "bg-neutral text-neutral-content shadow-sm",
                    else: "text-base-content/50 hover:text-base-content"
                  )
                ]}
              >
                <span class="icon-[tabler--table] size-3.5" />
                <span class="hidden sm:inline">{gettext("Table")}</span>
              </button>
              <button
                id="companies-view-cards"
                type="button"
                phx-click="set_view_mode"
                phx-value-mode="card"
                title={gettext("Card view")}
                class={[
                  "flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-medium transition-all",
                  if(@view_mode == :card,
                    do: "bg-neutral text-neutral-content shadow-sm",
                    else: "text-base-content/50 hover:text-base-content"
                  )
                ]}
              >
                <span class="icon-[tabler--layout-grid] size-3.5" />
                <span class="hidden sm:inline">{gettext("Cards")}</span>
              </button>
            </div>
          </div>
        </div>

        <%!-- Content: table or card view --%>
        <.async_result :let={_stream_key} assign={@companies}>
          <:loading>
            <%= if @view_mode == :card do %>
              <div
                id="companies-loading-cards"
                class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
                aria-busy="true"
              >
                <div
                  :for={row <- 1..8}
                  id={"company-card-skeleton-#{row}"}
                  class="flex flex-col overflow-hidden rounded-2xl border border-base-content/10 bg-base-100 shadow-sm"
                >
                  <div class="h-1 w-full bg-base-content/10" />
                  <div class="flex flex-1 flex-col gap-4 p-5">
                    <div class="flex items-start gap-3">
                      <div class="skeleton size-12 shrink-0 rounded-xl" />
                      <div class="flex-1 space-y-2 pt-0.5">
                        <div class="skeleton h-4 w-28 rounded-md" />
                        <div class="skeleton h-3 w-16 rounded-full" />
                      </div>
                    </div>
                    <div class="space-y-2">
                      <div class="skeleton h-3 w-32 rounded-md" />
                      <div class="skeleton h-3 w-20 rounded-md" />
                    </div>
                  </div>
                </div>
              </div>
            <% else %>
              <div
                id="companies-loading"
                class="overflow-x-auto rounded-xl border border-base-content/20 bg-base-100"
                aria-busy="true"
                aria-label={gettext("Loading companies")}
              >
                <table class="table w-full min-w-[53rem] table-fixed">
                  <.companies_table_header sort_by={@sort_by} sort_dir={@sort_dir} />
                  <tbody class="divide-y divide-base-content/8">
                    <tr
                      :for={row <- 1..6}
                      id={"company-skeleton-#{row}"}
                      class="divide-x divide-base-content/8"
                    >
                      <td class="px-4 py-3">
                        <div class="flex items-center gap-3">
                          <div class="skeleton size-8 shrink-0 rounded-lg" />
                          <div class="skeleton h-3.5 w-28 rounded-md" />
                        </div>
                      </td>
                      <td class="px-4 py-3">
                        <div class="skeleton h-5 w-16 rounded-full" />
                      </td>
                      <td class="hidden px-4 py-3 lg:table-cell">
                        <div class="skeleton h-3.5 w-24 rounded-md" />
                      </td>
                      <td class="px-4 py-3">
                        <div class="skeleton h-3.5 w-8 rounded-md" />
                      </td>
                      <td class="hidden px-4 py-3 md:table-cell">
                        <div class="skeleton h-3.5 w-20 rounded-md" />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          </:loading>
          <:failed :let={_reason}>
            <div
              id="companies-error"
              class="rounded-xl border border-error/30 bg-error/5 px-6 py-12 text-center"
              role="alert"
            >
              <.icon name="icon-[tabler--alert-circle]" class="mx-auto mb-3 size-8 text-error" />
              <p class="font-medium text-error">{gettext("Failed to load companies")}</p>
              <p class="mt-1 text-sm text-base-content/50">
                {gettext("Please refresh the page and try again.")}
              </p>
            </div>
          </:failed>

          <%= if @view_mode == :card do %>
            <%!-- Empty state (outside stream) --%>
            <div
              :if={@total == 0 and !@companies.loading}
              id="companies-cards-empty"
              class="flex flex-col items-center rounded-xl border border-base-content/20 bg-base-100 py-20 text-center"
            >
              <span class="icon-[tabler--building-off] mb-4 size-12 text-base-content/20" />
              <p class="text-sm font-medium text-base-content/50">
                {if @filters_active?,
                  do: gettext("No companies match these filters."),
                  else: gettext("No companies yet. Add your first one!")}
              </p>
              <p :if={!@filters_active?} class="mt-1 text-xs text-base-content/30">
                {gettext("Click \"New Company\" to get started.")}
              </p>
            </div>

            <%!-- Card grid --%>
            <div
              id="companies-cards"
              phx-update="stream"
              class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
            >
              <div
                :for={{id, company} <- @streams.companies}
                id={id}
                class="group relative flex flex-col overflow-hidden rounded-2xl border border-base-content/10 bg-base-100 shadow-sm transition-all duration-200 hover:-translate-y-0.5 hover:border-primary/30 hover:shadow-md"
              >
                <% linkedin_url = filled_url(company.linkedin_url) %>
                <div class="h-1 w-full bg-gradient-to-r from-primary/60 to-primary/20" />

                <%!-- Header: avatar + name + industry --%>
                <div class="flex flex-1 flex-col gap-4 p-5">
                  <div class="flex items-start gap-3">
                    <.link
                      navigate={show_path(company, @return_to)}
                      class="flex size-12 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-primary/20 to-primary/10 text-lg font-bold uppercase text-primary shadow-inner"
                    >
                      {company_initials(company.name)}
                    </.link>
                    <div class="min-w-0 flex-1 pt-0.5">
                      <div class="flex min-w-0 items-center gap-1.5">
                        <.link
                          navigate={show_path(company, @return_to)}
                          class="min-w-0 flex-1 truncate text-sm font-semibold text-base-content decoration-primary/50 underline-offset-2 transition-colors group-hover:text-primary group-hover:underline"
                        >
                          {company.name}
                        </.link>
                        <a
                          :if={linkedin_url}
                          id={"company-card-linkedin-#{company.id}"}
                          href={linkedin_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          title={gettext("LinkedIn")}
                          aria-label={gettext("Open LinkedIn company page")}
                          class="flex size-6 shrink-0 items-center justify-center rounded-md text-[#0A66C2] opacity-85 transition-all hover:bg-[#0A66C2]/10 hover:opacity-100"
                        >
                          <.icon name="icon-[tabler--brand-linkedin]" class="size-4" />
                        </a>
                        <div
                          id={"company-card-menu-#{id}"}
                          phx-hook="RowMenu"
                          class="relative shrink-0"
                        >
                          <button
                            type="button"
                            data-toggle
                            class="flex size-6 items-center justify-center rounded-md text-base-content/30 transition-colors hover:bg-base-content/8 hover:text-base-content"
                            aria-label={gettext("Actions")}
                          >
                            <.icon name="icon-[tabler--dots-vertical]" class="size-3.5" />
                          </button>
                          <ul
                            data-panel
                            class="row-menu-closed absolute right-0 z-50 w-44 overflow-hidden rounded-xl border border-base-content/15 bg-base-100 p-1 shadow-xl shadow-base-content/10"
                            role="menu"
                          >
                            <li>
                              <.link
                                patch={edit_path(company, @return_to)}
                                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-primary/10 hover:text-primary"
                              >
                                <.icon name="icon-[tabler--pencil]" class="size-3.5" />
                                {gettext("Edit")}
                              </.link>
                            </li>
                            <li>
                              <%= if is_nil(company.archived_at) do %>
                                <.link
                                  phx-click="archive"
                                  phx-value-id={company.id}
                                  class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-warning/10 hover:text-warning"
                                >
                                  <.icon name="icon-[tabler--archive]" class="size-3.5" />
                                  {gettext("Archive")}
                                </.link>
                              <% else %>
                                <.link
                                  phx-click="restore"
                                  phx-value-id={company.id}
                                  class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-warning/10 hover:text-warning"
                                >
                                  <.icon name="icon-[tabler--archive-off]" class="size-3.5" />
                                  {gettext("Restore")}
                                </.link>
                              <% end %>
                            </li>
                            <li>
                              <.link
                                phx-click="delete"
                                phx-value-id={company.id}
                                data-confirm={
                                  gettext(
                                    "Delete this company? Contacts will be kept without a company."
                                  )
                                }
                                class="danger-action flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-colors"
                              >
                                <.icon name="icon-[tabler--trash]" class="size-3.5" />
                                {gettext("Delete")}
                              </.link>
                            </li>
                          </ul>
                        </div>
                      </div>
                      <span
                        :if={company.industry}
                        class="mt-1 inline-flex w-full items-center gap-1.5 rounded-md border border-primary/15 bg-primary/8 px-2 py-0.5 text-xs font-medium text-base-content/70"
                      >
                        <.icon name="icon-[tabler--category]" class="size-3 shrink-0 text-primary" />
                        <span class="truncate">{company.industry}</span>
                      </span>
                      <span :if={!company.industry} class="mt-0.5 text-xs text-base-content/30">
                        {gettext("No industry")}
                      </span>
                    </div>
                  </div>

                  <%!-- Details --%>
                  <div class="flex-1 space-y-2 text-sm">
                    <div :if={company.website} class="flex items-center gap-2 text-base-content/60">
                      <span class="icon-[tabler--world] size-3.5 shrink-0 text-base-content/30" />
                      <a
                        href={company.website}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="truncate text-primary hover:underline"
                      >
                        {display_host(company.website)}
                      </a>
                    </div>
                    <div :if={company.phone} class="flex items-center gap-2 text-base-content/60">
                      <span class="icon-[tabler--phone] size-3.5 shrink-0 text-base-content/30" />
                      <span class="truncate">{company.phone}</span>
                    </div>
                    <div class="flex items-center gap-2 text-base-content/50">
                      <span class="icon-[tabler--users] size-3.5 shrink-0 text-base-content/30" />
                      <span>
                        {gettext("%{count} contacts", count: company.contact_count)}
                      </span>
                    </div>
                    <div class="flex items-center gap-2 text-xs text-base-content/40">
                      <span class="icon-[tabler--calendar] size-3.5 shrink-0" />
                      <span>{Calendar.strftime(company.inserted_at, "%b %-d, %Y")}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <div
              id="companies-table"
              phx-hook="NameTip"
              class="overflow-x-auto rounded-xl border border-base-content/20 bg-base-100"
            >
              <table class="table w-full min-w-[53rem] table-fixed">
                <.companies_table_header sort_by={@sort_by} sort_dir={@sort_dir} />
                <tbody id="companies" phx-update="stream" class="divide-y divide-base-content/8">
                  <tr :if={!@companies.loading} id="companies-empty" class="hidden only:table-row">
                    <td colspan="5" class="px-4 py-16 text-center">
                      <.icon
                        name="icon-[tabler--building-off]"
                        class="mx-auto mb-3 size-10 text-base-content/20"
                      />
                      <p class="text-sm font-medium text-base-content/50">
                        {if @filters_active?,
                          do: gettext("No companies match these filters."),
                          else: gettext("No companies yet. Add your first one!")}
                      </p>
                    </td>
                  </tr>
                  <tr
                    :for={{id, company} <- @streams.companies}
                    id={id}
                    class="group divide-x divide-base-content/8 transition-colors hover:bg-base-200/40"
                  >
                    <%!-- Company name + row menu --%>
                    <td class="relative px-4 py-3">
                      <div class="flex items-center gap-3 pr-8">
                        <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-xs font-bold uppercase text-primary">
                          {String.first(company.name || "?")}
                        </span>
                        <div class="min-w-0 flex-1">
                          <.link
                            navigate={show_path(company, @return_to)}
                            data-full-name={company.name}
                            class="block truncate text-sm font-medium decoration-primary/60 underline-offset-2 transition-colors hover:text-primary hover:underline"
                          >
                            {company.name}
                          </.link>
                        </div>
                      </div>
                      <div
                        id={"row-menu-#{id}"}
                        phx-hook="RowMenu"
                        class="absolute inset-y-0 right-3 flex items-center"
                      >
                        <button
                          type="button"
                          data-toggle
                          class="flex size-7 cursor-pointer items-center justify-center rounded-md text-base-content/40 transition-colors hover:bg-base-content/10 hover:text-base-content"
                          aria-label={gettext("Actions")}
                        >
                          <.icon name="icon-[tabler--dots-vertical]" class="size-4" />
                        </button>
                        <ul
                          data-panel
                          class="row-menu-closed z-50 w-44 overflow-hidden rounded-lg border border-base-content/15 bg-base-100 p-1 shadow-xl shadow-base-content/10"
                          role="menu"
                        >
                          <li>
                            <.link
                              patch={edit_path(company, @return_to)}
                              class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-primary/10 hover:text-primary"
                            >
                              <.icon name="icon-[tabler--pencil]" class="size-3.5" />
                              {gettext("Edit")}
                            </.link>
                          </li>
                          <li>
                            <%= if is_nil(company.archived_at) do %>
                              <.link
                                phx-click="archive"
                                phx-value-id={company.id}
                                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-warning/10 hover:text-warning"
                              >
                                <.icon name="icon-[tabler--archive]" class="size-3.5" />
                                {gettext("Archive")}
                              </.link>
                            <% else %>
                              <.link
                                phx-click="restore"
                                phx-value-id={company.id}
                                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-warning/10 hover:text-warning"
                              >
                                <.icon name="icon-[tabler--archive-off]" class="size-3.5" />
                                {gettext("Restore")}
                              </.link>
                            <% end %>
                          </li>
                          <li>
                            <.link
                              phx-click="delete"
                              phx-value-id={company.id}
                              data-confirm={
                                gettext(
                                  "Delete this company? Contacts will be kept without a company."
                                )
                              }
                              class="danger-action flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-colors"
                            >
                              <.icon name="icon-[tabler--trash]" class="size-3.5" />
                              {gettext("Delete")}
                            </.link>
                          </li>
                        </ul>
                      </div>
                    </td>

                    <%!-- Industry --%>
                    <td class="px-4 py-3">
                      <span
                        :if={company.industry}
                        class="inline-flex h-7 w-full items-center gap-1.5 rounded-md border border-primary/15 bg-primary/8 px-2 text-xs font-medium text-base-content/70"
                      >
                        <.icon name="icon-[tabler--category]" class="size-3.5 shrink-0 text-primary" />
                        <span class="truncate">{company.industry}</span>
                      </span>
                      <span :if={!company.industry} class="text-base-content/25">—</span>
                    </td>

                    <%!-- Website --%>
                    <td class="hidden px-4 py-3 lg:table-cell">
                      <a
                        :if={company.website}
                        href={company.website}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="truncate text-sm text-primary hover:underline"
                      >
                        {display_host(company.website)}
                      </a>
                      <span :if={!company.website} class="text-sm text-base-content/25">—</span>
                    </td>

                    <%!-- Contacts count --%>
                    <td class="px-4 py-3 text-sm text-base-content/60">
                      <span class="inline-flex items-center gap-1.5">
                        <span class="icon-[tabler--users] size-3.5 text-base-content/40" />
                        {company.contact_count}
                      </span>
                    </td>

                    <%!-- Date --%>
                    <td class="hidden px-4 py-3 text-sm text-base-content/60 md:table-cell">
                      {Calendar.strftime(company.inserted_at, "%b %-d, %Y")}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </.async_result>

        <%!-- Footer: count + pagination --%>
        <div
          :if={@companies.ok? and !@companies.loading and @total > 0}
          id="companies-footer"
          class="mt-6 flex flex-wrap items-center justify-between gap-3"
        >
          <p class="text-sm text-base-content/50">
            <%= if @total == 0 do %>
              {gettext("No companies found")}
            <% else %>
              {gettext("Showing %{from}–%{to} of %{total}",
                from: @page_from,
                to: @page_to,
                total: @total
              )}
            <% end %>
          </p>
          <nav :if={@total_pages > 1} aria-label={gettext("Pagination")}>
            <ul class="flex items-center gap-0.5 rounded-xl border border-base-content/10 bg-base-100 p-1 shadow-sm">
              <li>
                <button
                  phx-click="page"
                  phx-value-n={@page - 1}
                  disabled={@page == 1}
                  class="flex h-8 w-8 items-center justify-center rounded-lg bg-base-content text-base-100 transition-all hover:opacity-80 disabled:pointer-events-none disabled:opacity-20"
                  aria-label={gettext("Previous page")}
                >
                  <span class="icon-[tabler--chevron-left] size-4" />
                </button>
              </li>

              <li :for={n <- @page_numbers}>
                <%= if n == :gap do %>
                  <span class="flex h-8 w-8 items-center justify-center select-none text-sm text-base-content/30">
                    …
                  </span>
                <% else %>
                  <button
                    phx-click="page"
                    phx-value-n={n}
                    aria-current={if(n == @page, do: "page")}
                    class={[
                      "flex h-8 w-8 items-center justify-center rounded-lg text-sm font-medium transition-all select-none",
                      if(n == @page,
                        do: "bg-primary text-primary-content shadow-sm ring-1 ring-primary/30",
                        else: "text-base-content/60 hover:bg-primary/10 hover:text-primary"
                      )
                    ]}
                  >
                    {n}
                  </button>
                <% end %>
              </li>

              <li>
                <button
                  phx-click="page"
                  phx-value-n={@page + 1}
                  disabled={@page >= @total_pages}
                  class="flex h-8 w-8 items-center justify-center rounded-lg bg-base-content text-base-100 transition-all hover:opacity-80 disabled:pointer-events-none disabled:opacity-20"
                  aria-label={gettext("Next page")}
                >
                  <span class="icon-[tabler--chevron-right] size-4" />
                </button>
              </li>
            </ul>
          </nav>
        </div>
      </Layouts.page>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="company-modal"
        show
        on_cancel={hide_modal("company-modal") |> JS.patch(@return_to)}
      >
        <.live_component
          module={KonevoWeb.CompaniesLive.FormComponent}
          id={if @company.id, do: @company.id, else: :new}
          title={if @live_action == :new, do: gettext("New Company"), else: gettext("Edit Company")}
          action={@live_action}
          company={@company}
          current_scope={@current_scope}
          patch={@return_to}
        />
      </.modal>
    </Layouts.app>
    """
  end

  attr(:sort_by, :atom, required: true)
  attr(:sort_dir, :atom, required: true)

  defp companies_table_header(assigns) do
    ~H"""
    <colgroup>
      <col />
      <col class="w-36" />
      <col class="w-48" />
      <col class="w-28" />
      <col class="w-36" />
    </colgroup>
    <thead>
      <tr class="divide-x divide-base-content/15 border-b border-secondary/35 bg-secondary/10">
        <th
          :for={
            {label, column, extra} <- [
              {gettext("Company"), :name, nil},
              {gettext("Industry"), :industry, nil},
              {gettext("Website"), nil, "hidden lg:table-cell"},
              {gettext("Contacts"), :contacts, nil},
              {gettext("Date"), :inserted_at, "hidden md:table-cell"}
            ]
          }
          class={["px-4 py-3 text-left", extra]}
        >
          <%= if column do %>
            <button
              phx-click="sort"
              phx-value-by={column}
              class={[
                "flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide transition-colors select-none",
                if(@sort_by == column,
                  do: "text-primary",
                  else: "text-base-content/60 hover:text-base-content"
                )
              ]}
            >
              {label}
              <.sort_icon active={@sort_by == column} dir={@sort_dir} />
            </button>
          <% else %>
            <span class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
              {label}
            </span>
          <% end %>
        </th>
      </tr>
    </thead>
    """
  end

  attr(:active, :boolean, required: true)
  attr(:dir, :atom, required: true)

  defp sort_icon(assigns) do
    ~H"""
    <%= cond do %>
      <% @active and @dir == :asc -> %>
        <span class="icon-[tabler--arrow-up] size-3 text-primary" />
      <% @active and @dir == :desc -> %>
        <span class="icon-[tabler--arrow-down] size-3 text-primary" />
      <% true -> %>
        <span class="icon-[tabler--arrows-sort] size-3 opacity-30" />
    <% end %>
    """
  end

  defp parse_view_mode("card"), do: :card
  defp parse_view_mode(_), do: :table

  defp company_initials(nil), do: "?"

  defp company_initials(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  defp display_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _other -> url
    end
  end

  defp filled_url(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      url -> url
    end
  end

  defp filled_url(_value), do: nil
end
