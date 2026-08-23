defmodule KonevoWeb.ContactsLive.Index do
  use KonevoWeb, :live_view

  alias Konevo.Accounts
  alias Konevo.Companies
  alias Konevo.Contacts
  alias Konevo.Contacts.Contact
  alias Konevo.Uploads

  @per_page 25
  @all_statuses [:lead, :prospect, :customer, :churned]
  @sortable_columns ~w(name email status inserted_at)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    view_mode = parse_view_mode(user.contacts_view_mode)

    {:ok,
     socket
     |> assign(:page_title, gettext("Contacts"))
     |> assign(:view_mode, view_mode)
     |> assign(:search, "")
     |> assign(:archive_filter, :active)
     |> assign(:statuses, [])
     |> assign(:company_ids, [])
     |> assign(:company_search, "")
     |> assign(:company_suggestions, [])
     |> assign(:created_from, "")
     |> assign(:created_to, "")
     |> assign(:sort_by, :name)
     |> assign(:sort_dir, :asc)
     |> assign(:page, 1)
     |> assign(:total, 0)
     |> assign(:contacts_request_ref, nil)
     |> assign(:contact, nil)
     |> stream(:contacts, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket = apply_action(socket, socket.assigns.live_action, params)

    {:noreply, load_contacts(socket, params)}
  end

  defp load_contacts(socket, params) do
    %{
      search: search,
      archive_filter: archive_filter,
      statuses: statuses,
      company_ids: company_ids,
      created_from: created_from,
      created_to: created_to,
      sort_by: sort_by,
      sort_dir: sort_dir,
      page: page
    } = parse_filter_params(params)

    scope = socket.assigns.current_scope
    live_view = self()
    request_ref = make_ref()

    opts = [
      search: search,
      archive_filter: archive_filter,
      statuses: statuses,
      company_ids: company_ids,
      created_from: created_from,
      created_to: created_to,
      sort_by: sort_by,
      sort_dir: sort_dir,
      page: page,
      per_page: @per_page
    ]

    socket
    |> assign(:search, search)
    |> assign(:archive_filter, archive_filter)
    |> assign(:statuses, statuses)
    |> assign(:company_ids, company_ids)
    |> assign(:created_from, created_from)
    |> assign(:created_to, created_to)
    |> assign(
      :company_suggestions,
      Companies.search_companies(scope, socket.assigns.company_search)
    )
    |> assign(:sort_by, sort_by)
    |> assign(:sort_dir, sort_dir)
    |> assign(:page, page)
    |> assign(:contacts_request_ref, request_ref)
    |> cancel_async(:contacts)
    |> stream_async(:contacts, fn ->
      {contacts, total} = Contacts.list_contacts(scope, opts)

      case Uploads.attach_contact_avatars(scope, contacts) do
        {:ok, contacts} ->
          send(live_view, {:contacts_total, request_ref, total})
          {:ok, contacts, reset: true}

        {:error, :unauthorized} ->
          {:error, :unauthorized}
      end
    end)
  end

  defp parse_filter_params(params) do
    %{
      search: Map.get(params, "search", ""),
      archive_filter: parse_archive_filter(Map.get(params, "archived", "")),
      statuses: parse_statuses(Map.get(params, "statuses", "")),
      company_ids: parse_company_ids(Map.get(params, "company_ids", "")),
      created_from: parse_date_param(Map.get(params, "created_from", "")),
      created_to: parse_date_param(Map.get(params, "created_to", "")),
      sort_by: parse_sort_by(Map.get(params, "sort_by", "")),
      sort_dir: parse_sort_dir(Map.get(params, "sort_dir", "")),
      page: parse_page(Map.get(params, "page", ""))
    }
  end

  defp parse_statuses(""), do: []

  defp parse_statuses(str) when is_binary(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn
      "lead" -> [:lead]
      "prospect" -> [:prospect]
      "customer" -> [:customer]
      "churned" -> [:churned]
      _ -> []
    end)
  end

  defp parse_company_ids(""), do: []

  defp parse_company_ids(str) when is_binary(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn s ->
      case Integer.parse(s) do
        {id, ""} -> [id]
        _ -> []
      end
    end)
  end

  defp parse_sort_by(col) when col in @sortable_columns,
    do: String.to_existing_atom(col)

  defp parse_sort_by(_), do: :name

  defp parse_sort_dir("desc"), do: :desc
  defp parse_sort_dir(_), do: :asc

  defp parse_page(str) when is_binary(str) and str != "" do
    case Integer.parse(str) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

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

  defp apply_action(socket, :edit, %{"id" => id}) do
    contact = Contacts.get_contact_by_slug_or_id!(socket.assigns.current_scope, id)
    assign(socket, :contact, contact)
  end

  defp apply_action(socket, :new, _params) do
    assign(socket, :contact, %Contact{})
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :contact, nil)
  end

  @impl true
  def handle_info({KonevoWeb.ContactsLive.FormComponent, {:saved, contact, :updated}}, socket) do
    contact = contact_with_avatar(socket, contact.id)

    {:noreply,
     socket
     |> put_flash(:success, gettext("Contact updated successfully"))
     |> stream_insert(:contacts, contact)
     |> push_patch(to: ~p"/contacts")}
  end

  def handle_info({:contacts_total, request_ref, total}, socket) do
    if request_ref == socket.assigns.contacts_request_ref do
      {:noreply, assign(socket, :total, total)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({KonevoWeb.ContactsLive.FormComponent, {:saved, contact, :created}}, socket) do
    contact = contact_with_avatar(socket, contact.id)

    {:noreply,
     socket
     |> put_flash(:success, gettext("Contact created successfully"))
     |> update(:total, &(&1 + 1))
     |> stream_insert(:contacts, contact)
     |> push_patch(to: ~p"/contacts")}
  end

  defp contact_with_avatar(socket, contact_id) do
    scope = socket.assigns.current_scope
    contact = Contacts.get_contact!(scope, contact_id)
    {:ok, [contact]} = Uploads.attach_contact_avatars(scope, [contact])
    contact
  end

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

  def handle_event("toggle_status", %{"status" => status_str}, socket) do
    status = String.to_existing_atom(status_str)
    current = socket.assigns.statuses

    new_statuses =
      if status in current,
        do: List.delete(current, status),
        else: [status | current]

    {:noreply, push_patch(socket, to: build_url(socket, %{statuses: new_statuses, page: 1}))}
  end

  def handle_event("toggle_all_statuses", _, socket) do
    new_statuses =
      if length(socket.assigns.statuses) == length(@all_statuses),
        do: [],
        else: @all_statuses

    {:noreply, push_patch(socket, to: build_url(socket, %{statuses: new_statuses, page: 1}))}
  end

  def handle_event("toggle_company", %{"id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} ->
        current = socket.assigns.company_ids
        new_ids = if id in current, do: List.delete(current, id), else: [id | current]
        {:noreply, push_patch(socket, to: build_url(socket, %{company_ids: new_ids, page: 1}))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("search_companies", %{"q" => q}, socket) do
    scope = socket.assigns.current_scope
    suggestions = Companies.search_companies(scope, q)

    {:noreply,
     socket
     |> assign(:company_search, q)
     |> assign(:company_suggestions, suggestions)}
  end

  def handle_event("filter_date_range", %{"from" => from, "to" => to}, socket) do
    from = parse_date_param(from)
    to = parse_date_param(to)

    {:noreply,
     push_patch(socket, to: build_url(socket, %{created_from: from, created_to: to, page: 1}))}
  end

  def handle_event("clear_filters", _, socket) do
    socket =
      socket
      |> push_patch(
        to:
          build_url(socket, %{
            statuses: [],
            archive_filter: :active,
            company_ids: [],
            created_from: "",
            created_to: "",
            page: 1
          })
      )
      |> push_event("date_range:clear", %{})

    {:noreply, socket}
  end

  def handle_event("sort", %{"by" => by}, socket) do
    sort_by = parse_sort_by(by)

    sort_dir =
      if socket.assigns.sort_by == sort_by do
        if socket.assigns.sort_dir == :asc, do: :desc, else: :asc
      else
        :asc
      end

    {:noreply,
     push_patch(socket, to: build_url(socket, %{sort_by: sort_by, sort_dir: sort_dir, page: 1}))}
  end

  def handle_event("page", %{"n" => n_str}, socket) do
    case Integer.parse(n_str) do
      {n, ""} when n > 0 ->
        {:noreply, push_patch(socket, to: build_url(socket, %{page: n}))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    contact = Contacts.get_contact!(socket.assigns.current_scope, id)
    {:ok, _} = Contacts.delete_contact(socket.assigns.current_scope, contact)
    {:noreply, stream_delete(socket, :contacts, contact)}
  end

  def handle_event("archive", %{"id" => id}, socket) do
    contact = Contacts.get_contact!(socket.assigns.current_scope, id)

    case Contacts.archive_contact(socket.assigns.current_scope, contact) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:success, gettext("Contact archived"))
         |> apply_contact_archive_change(contact, updated)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Not allowed"))}
    end
  end

  def handle_event("restore", %{"id" => id}, socket) do
    contact = Contacts.get_contact!(socket.assigns.current_scope, id)

    case Contacts.restore_contact(socket.assigns.current_scope, contact) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:success, gettext("Contact restored"))
         |> apply_contact_archive_change(contact, updated)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Not allowed"))}
    end
  end

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    view_mode = parse_view_mode(mode)
    user = socket.assigns.current_scope.user
    Accounts.update_user_view_preferences(user, %{contacts_view_mode: mode})

    {:noreply,
     socket
     |> assign(:view_mode, view_mode)
     |> push_patch(to: build_url(socket, %{}))}
  end

  defp parse_view_mode("card"), do: :card
  defp parse_view_mode(_), do: :table

  defp build_url(socket, overrides) do
    search = Map.get(overrides, :search, socket.assigns.search)
    archive_filter = Map.get(overrides, :archive_filter, socket.assigns.archive_filter)
    statuses = Map.get(overrides, :statuses, socket.assigns.statuses)
    company_ids = Map.get(overrides, :company_ids, socket.assigns.company_ids)
    created_from = Map.get(overrides, :created_from, socket.assigns.created_from)
    created_to = Map.get(overrides, :created_to, socket.assigns.created_to)
    sort_by = Map.get(overrides, :sort_by, socket.assigns.sort_by)
    sort_dir = Map.get(overrides, :sort_dir, socket.assigns.sort_dir)
    page = Map.get(overrides, :page, socket.assigns.page)

    params =
      []
      |> push_param("search", search, "")
      |> push_param("archived", archive_filter_param(archive_filter), "active")
      |> push_param("statuses", Enum.join(statuses, ","), "")
      |> push_param("company_ids", Enum.join(company_ids, ","), "")
      |> push_param("created_from", created_from, "")
      |> push_param("created_to", created_to, "")
      |> push_param("sort_by", to_string(sort_by), "name")
      |> push_param("sort_dir", to_string(sort_dir), "asc")
      |> push_param("page", to_string(page), "1")
      |> Map.new()

    if map_size(params) == 0, do: ~p"/contacts", else: ~p"/contacts?#{params}"
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

  defp apply_contact_archive_change(socket, old_contact, updated_contact) do
    case socket.assigns.archive_filter do
      :all ->
        contact = contact_with_avatar(socket, updated_contact.id)
        stream_insert(socket, :contacts, contact)

      _ ->
        socket
        |> update(:total, &max(&1 - 1, 0))
        |> stream_delete(:contacts, old_contact)
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
      |> assign(:all_statuses, @all_statuses)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.page title={@page_title}>
        <:actions>
          <.button patch={~p"/contacts/new"} class="btn btn-primary btn-sm gap-1.5">
            <span class="icon-[tabler--plus] size-4" />
            {gettext("New Contact")}
          </.button>
        </:actions>

        <%!-- Toolbar --%>
        <div class="mb-4 flex flex-wrap items-center gap-2">
          <%!-- Search --%>
          <div class="relative w-52 shrink-0">
            <span class="icon-[tabler--search] pointer-events-none absolute left-2.5 top-1/2 z-10 size-3.5 -translate-y-1/2 text-base-content/40" />
            <form phx-change="search" phx-submit="search" id="contact-search-form">
              <input
                type="text"
                name="q"
                value={@search}
                placeholder={gettext("Search by name, email")}
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
              class="absolute right-2.5 top-1/2 -translate-y-1/2 text-base-content/40 hover:text-base-content transition-colors"
            >
              <span class="icon-[tabler--x] size-3.5" />
            </button>
          </div>

          <.archive_filter_dropdown
            id="contacts-archive-filter"
            selected={@archive_filter}
            options={archive_filter_options()}
          />

          <%!-- Filter dropdowns --%>
          <%!-- Mobile filter toggle --%>
          <button
            type="button"
            class={[
              "btn btn-sm gap-1.5 border select-none sm:hidden",
              if(@statuses != [] or @company_ids != [] or @created_from != "" or @created_to != "",
                do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                else:
                  "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
              )
            ]}
            phx-click={
              JS.toggle(
                to: "#contacts-filter-panel",
                display: "flex",
                in:
                  {"transition ease-out duration-200", "opacity-0 -translate-y-1",
                   "opacity-100 translate-y-0"},
                out:
                  {"transition ease-in duration-150", "opacity-100 translate-y-0",
                   "opacity-0 -translate-y-1"}
              )
              |> JS.toggle_class("rotate-180", to: "#contacts-filter-chevron")
            }
          >
            <span class="icon-[tabler--adjustments-horizontal] size-3.5" />
            {gettext("Filters")}
            <span
              :if={@statuses != [] or @company_ids != [] or @created_from != "" or @created_to != ""}
              class="flex size-4 items-center justify-center rounded-full bg-primary text-[10px] font-bold text-primary-content"
            >
              {length(@statuses) + length(@company_ids) + if(@created_from != "", do: 1, else: 0) +
                if @created_to != "", do: 1, else: 0}
            </span>
            <span
              id="contacts-filter-chevron"
              class="icon-[tabler--chevron-down] size-3.5 opacity-50 transition-transform duration-200"
            />
          </button>
          <div
            id="contacts-filter-panel"
            class="hidden flex-wrap items-center gap-2 sm:flex"
          >
            <%!-- Status filter --%>
            <div class="relative" id="status-filter-dropdown" phx-hook="FilterPanel">
              <button
                type="button"
                data-toggle
                class={[
                  "btn btn-sm gap-1.5 border select-none transition-all",
                  if(@statuses != [],
                    do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                    else:
                      "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                  )
                ]}
              >
                <span class="icon-[tabler--filter] size-3.5" />
                {gettext("Status")}
                <span
                  :if={@statuses != []}
                  class="flex size-4 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-content"
                >
                  {length(@statuses)}
                </span>
                <span class="icon-[tabler--chevron-down] size-3.5 opacity-50" />
              </button>

              <div
                data-panel
                class="row-menu-closed z-30 min-w-52 overflow-hidden rounded-xl border border-base-content/20 bg-base-100 shadow-xl"
              >
                <label class="flex w-full cursor-pointer select-none items-center gap-3 px-3 py-2.5 hover:bg-base-200 transition-colors">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-xs checkbox-primary shrink-0"
                    checked={length(@statuses) == length(@all_statuses)}
                    phx-click="toggle_all_statuses"
                    data-select-all
                  />
                  <span class="text-sm font-semibold">{gettext("Select all")}</span>
                </label>
                <div class="mx-2 border-t border-base-content/10" />
                <div class="p-1">
                  <label
                    :for={status <- @all_statuses}
                    class="flex w-full cursor-pointer select-none items-center gap-3 rounded-lg px-3 py-2 hover:bg-base-200 transition-colors"
                  >
                    <input
                      type="checkbox"
                      class="checkbox checkbox-xs checkbox-primary shrink-0"
                      checked={status in @statuses}
                      phx-click="toggle_status"
                      phx-value-status={status}
                      data-select-option
                    />
                    <span class={["size-2 rounded-full shrink-0", status_dot_class(status)]} />
                    <span class="text-sm">{Phoenix.Naming.humanize(status)}</span>
                  </label>
                </div>
              </div>
            </div>

            <%!-- Company filter --%>
            <div class="relative" id="company-filter-dropdown" phx-hook="FilterPanel">
              <button
                type="button"
                data-toggle
                class={[
                  "btn btn-sm gap-1.5 border select-none transition-all",
                  if(@company_ids != [],
                    do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                    else:
                      "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                  )
                ]}
              >
                <span class="icon-[tabler--building] size-3.5" />
                {gettext("Company")}
                <span
                  :if={@company_ids != []}
                  class="flex size-4 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-content"
                >
                  {length(@company_ids)}
                </span>
                <span class="icon-[tabler--chevron-down] size-3.5 opacity-50" />
              </button>

              <div
                data-panel
                class="row-menu-closed z-30 w-64 overflow-hidden rounded-xl border border-base-content/20 bg-base-100 shadow-xl"
              >
                <div class="border-b border-base-content/10 p-2">
                  <form
                    phx-change="search_companies"
                    phx-submit="search_companies"
                    id="company-search-form"
                  >
                    <div class="relative">
                      <span class="icon-[tabler--search] pointer-events-none absolute left-2.5 top-1/2 z-10 size-3.5 -translate-y-1/2 text-base-content/40" />
                      <input
                        type="text"
                        name="q"
                        value={@company_search}
                        placeholder={gettext("Search companies...")}
                        phx-debounce="200"
                        class="input input-sm w-full pl-8"
                        autocomplete="off"
                      />
                    </div>
                  </form>
                </div>
                <div class="max-h-60 overflow-y-auto p-1">
                  <div
                    :if={@company_suggestions == []}
                    class="px-3 py-6 text-center text-sm text-base-content/40"
                  >
                    {gettext("No companies found")}
                  </div>
                  <label
                    :for={company <- @company_suggestions}
                    class="flex w-full cursor-pointer select-none items-center gap-3 rounded-lg px-3 py-2 hover:bg-base-200 transition-colors"
                  >
                    <input
                      type="checkbox"
                      class="checkbox checkbox-xs checkbox-primary shrink-0"
                      checked={company.id in @company_ids}
                      phx-click="toggle_company"
                      phx-value-id={company.id}
                    />
                    <span class="flex size-6 shrink-0 items-center justify-center rounded bg-base-200 text-xs font-bold uppercase text-base-content/60">
                      {String.first(company.name)}
                    </span>
                    <span class="truncate text-sm">{company.name}</span>
                  </label>
                </div>
              </div>
            </div>

            <%!-- Date range filter --%>
            <.date_range_picker
              id="created-date-filter"
              created_from={@created_from}
              created_to={@created_to}
            />

            <%!-- Clear all filters --%>
            <button
              :if={@statuses != [] or @company_ids != [] or @created_from != "" or @created_to != ""}
              phx-click="clear_filters"
              type="button"
              class="btn btn-sm gap-1.5 border border-base-content/20 bg-base-100 text-base-content/60 transition-all hover:border-base-content/30 hover:text-base-content"
            >
              <span class="icon-[tabler--x] size-3" />
              {gettext("Clear filters")}
            </button>
          </div>

          <%!-- View mode toggle --%>
          <div class="ml-auto flex items-center gap-1 rounded-lg border border-base-content/15 bg-base-100 p-1">
            <button
              type="button"
              phx-click="set_view_mode"
              phx-value-mode="table"
              class={[
                "flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-medium transition-all",
                if(@view_mode == :table,
                  do: "bg-neutral text-neutral-content shadow-sm",
                  else: "text-base-content/50 hover:text-base-content"
                )
              ]}
              title={gettext("Table view")}
            >
              <span class="icon-[tabler--table] size-3.5" />
              <span class="hidden sm:inline">{gettext("Table")}</span>
            </button>
            <button
              type="button"
              phx-click="set_view_mode"
              phx-value-mode="card"
              class={[
                "flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-medium transition-all",
                if(@view_mode == :card,
                  do: "bg-neutral text-neutral-content shadow-sm",
                  else: "text-base-content/50 hover:text-base-content"
                )
              ]}
              title={gettext("Card view")}
            >
              <span class="icon-[tabler--layout-grid] size-3.5" />
              <span class="hidden sm:inline">{gettext("Cards")}</span>
            </button>
          </div>
        </div>

        <%!-- Table / Card view --%>
        <.async_result :let={_stream_ready?} assign={@contacts}>
          <:loading>
            <%= if @view_mode == :card do %>
              <div
                id="contacts-loading-cards"
                class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
                aria-busy="true"
                aria-label={gettext("Loading contacts")}
              >
                <div
                  :for={i <- 1..8}
                  id={"contact-card-skeleton-#{i}"}
                  class="flex flex-col gap-3 rounded-2xl border border-base-content/10 bg-base-100 p-5"
                >
                  <div class="flex items-center gap-3">
                    <div class="skeleton size-12 shrink-0 rounded-full" />
                    <div class="flex-1 space-y-2">
                      <div class="skeleton h-4 w-28 rounded-md" />
                      <div class="skeleton h-3 w-16 rounded-full" />
                    </div>
                  </div>
                  <div class="skeleton h-3 w-40 rounded-md" />
                  <div class="skeleton h-3 w-32 rounded-md" />
                  <div class="skeleton h-3 w-20 rounded-md" />
                </div>
              </div>
            <% else %>
              <div
                id="contacts-loading"
                class="overflow-x-auto rounded-xl border border-base-content/20 bg-base-100"
                aria-busy="true"
                aria-label={gettext("Loading contacts")}
              >
                <table class="table w-full min-w-212 table-fixed">
                  <.contacts_table_header sort_by={@sort_by} sort_dir={@sort_dir} />
                  <tbody class="divide-y divide-base-content/8">
                    <tr
                      :for={row <- 1..6}
                      id={"contact-skeleton-#{row}"}
                      class="divide-x divide-base-content/8"
                    >
                      <td class="px-4 py-3">
                        <div class="flex items-center gap-3">
                          <div class="skeleton size-8 shrink-0 rounded-full" />
                          <div class="skeleton h-3.5 w-28 rounded-md" />
                        </div>
                      </td>
                      <td class="px-4 py-3">
                        <div class="skeleton h-3.5 w-40 rounded-md" />
                      </td>
                      <td class="px-4 py-3">
                        <div class="skeleton h-5 w-16 rounded-full" />
                      </td>
                      <td class="px-4 py-3">
                        <div class="skeleton h-3.5 w-24 rounded-md" />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          </:loading>
          <:failed :let={_reason}>
            <div
              id="contacts-load-error"
              class="rounded-xl border border-error/30 bg-error/5 px-6 py-12 text-center"
              role="alert"
            >
              <.icon name="icon-[tabler--alert-circle]" class="mx-auto mb-3 size-8 text-error" />
              <p class="font-medium text-error">{gettext("Failed to load contacts")}</p>
              <p class="mt-1 text-sm text-base-content/50">
                {gettext("Please refresh the page and try again.")}
              </p>
            </div>
          </:failed>

          <%= if @view_mode == :card do %>
            <%!-- Empty state --%>
            <div
              :if={@total == 0 and !@contacts.loading}
              id="contacts-cards-empty"
              class="flex flex-col items-center py-20 text-center"
            >
              <span class="icon-[tabler--users] mb-4 size-12 text-base-content/20" />
              <p class="text-sm font-medium text-base-content/50">
                {gettext("No contacts found.")}
              </p>
              <p class="mt-1 text-xs text-base-content/30">
                {gettext("Try adjusting your search or filters.")}
              </p>
            </div>

            <%!-- Card grid view --%>
            <div
              id="contacts-cards"
              phx-update="stream"
              class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
            >
              <div
                :for={{id, contact} <- @streams.contacts}
                id={id}
                class="group relative flex flex-col overflow-hidden rounded-2xl border border-base-content/10 bg-base-100 shadow-sm transition-all duration-200 hover:-translate-y-0.5 hover:border-primary/25 hover:shadow-md hover:shadow-primary/8"
              >
                <% linkedin_url = filled_url(contact.linkedin_url) %>
                <%!-- Card top accent --%>
                <div class={["h-2 w-full", status_card_accent(contact.status)]} />

                <%!-- Card body --%>
                <div class="flex flex-1 flex-col gap-4 p-5">
                  <%!-- Avatar + name row --%>
                  <div class="flex items-start gap-3">
                    <.link navigate={~p"/contacts/#{contact}"} class="shrink-0">
                      <%= if contact.avatar_id do %>
                        <img
                          src={~p"/uploads/avatar/#{contact.avatar_id}"}
                          alt=""
                          class="size-12 rounded-full bg-base-200 object-cover ring-2 ring-base-content/8"
                        />
                      <% else %>
                        <div class={[
                          "flex size-12 items-center justify-center rounded-full text-sm font-bold",
                          status_avatar_class(contact.status)
                        ]}>
                          {contact_initials(contact)}
                        </div>
                      <% end %>
                    </.link>
                    <div class="min-w-0 flex-1 pt-0.5">
                      <div class="flex items-center gap-1">
                        <.link
                          navigate={~p"/contacts/#{contact}"}
                          class="min-w-0 flex-1 truncate text-sm font-semibold text-base-content decoration-primary/50 underline-offset-2 transition-colors group-hover:text-primary group-hover:underline"
                        >
                          {"#{contact.first_name} #{contact.last_name}" |> String.trim()}
                        </.link>
                        <%!-- LinkedIn icon --%>
                        <a
                          :if={linkedin_url}
                          id={"contact-card-linkedin-#{contact.id}"}
                          href={linkedin_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          title={gettext("LinkedIn")}
                          aria-label={gettext("Open LinkedIn profile")}
                          class="flex size-6 shrink-0 items-center justify-center rounded-md text-[#0A66C2] opacity-85 transition-all hover:bg-[#0A66C2]/10 hover:opacity-100"
                        >
                          <.icon name="icon-[tabler--brand-linkedin]" class="size-4" />
                        </a>
                        <%!-- Dots menu --%>
                        <div
                          id={"contact-card-menu-#{id}"}
                          phx-hook="RowMenu"
                          class="relative shrink-0"
                        >
                          <button
                            type="button"
                            data-toggle
                            class="flex size-6 items-center justify-center rounded-md text-base-content/30 transition-colors hover:bg-base-content/8 hover:text-base-content"
                            aria-label={gettext("Actions")}
                          >
                            <span class="icon-[tabler--dots-vertical] size-3.5" />
                          </button>
                          <ul
                            data-panel
                            class="row-menu-closed absolute right-0 z-50 w-44 overflow-hidden rounded-xl border border-base-content/15 bg-base-100 p-1 shadow-xl shadow-base-content/10"
                            role="menu"
                          >
                            <li>
                              <.link
                                patch={~p"/contacts/#{contact}/edit/inline"}
                                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-primary/10 hover:text-primary"
                              >
                                <span class="icon-[tabler--pencil] size-3.5" />
                                {gettext("Edit")}
                              </.link>
                            </li>
                            <li>
                              <%= if is_nil(contact.archived_at) do %>
                                <button
                                  type="button"
                                  phx-click={JS.push("archive", value: %{id: contact.id})}
                                  class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-warning/10 hover:text-warning"
                                >
                                  <.icon name="icon-[tabler--archive]" class="size-3.5" />
                                  {gettext("Archive")}
                                </button>
                              <% else %>
                                <button
                                  type="button"
                                  phx-click={JS.push("restore", value: %{id: contact.id})}
                                  class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-success/10 hover:text-success"
                                >
                                  <.icon name="icon-[tabler--archive-off]" class="size-3.5" />
                                  {gettext("Restore")}
                                </button>
                              <% end %>
                            </li>
                            <li>
                              <button
                                type="button"
                                phx-click={JS.push("delete", value: %{id: contact.id})}
                                data-confirm={gettext("Are you sure?")}
                                class="danger-action flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-colors"
                              >
                                <span class="icon-[tabler--trash] size-3.5" />
                                {gettext("Delete")}
                              </button>
                            </li>
                          </ul>
                        </div>
                      </div>
                      <span class={[
                        "mt-1 inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium",
                        status_pill_class(contact.status)
                      ]}>
                        <span class="size-1.5 shrink-0 rounded-full bg-current" />
                        {Phoenix.Naming.humanize(contact.status)}
                      </span>
                    </div>
                  </div>

                  <%!-- Details --%>
                  <div class="space-y-2">
                    <div
                      :if={contact.email}
                      class="flex min-w-0 items-center gap-2 text-xs text-base-content/60"
                    >
                      <span class="icon-[tabler--mail] size-3.5 shrink-0 text-base-content/35" />
                      <span class="truncate">{contact.email}</span>
                    </div>
                    <div
                      :if={contact.company}
                      class="flex items-center gap-2 text-xs text-base-content/60"
                    >
                      <span class="icon-[tabler--building] size-3.5 shrink-0 text-base-content/35" />
                      <span class="truncate">{contact.company.name}</span>
                    </div>
                    <div class="flex items-center gap-2 text-xs text-base-content/40">
                      <span class="icon-[tabler--calendar] size-3.5 shrink-0" />
                      <span>{Calendar.strftime(contact.inserted_at, "%b %-d, %Y")}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <%!-- Table view --%>
            <div
              id="contacts-table"
              phx-hook="NameTip"
              class="overflow-x-auto rounded-xl border border-base-content/20 bg-base-100"
            >
              <table class="table w-full min-w-212 table-fixed">
                <.contacts_table_header sort_by={@sort_by} sort_dir={@sort_dir} />

                <tbody id="contacts" phx-update="stream" class="divide-y divide-base-content/8">
                  <tr :if={!@contacts.loading} id="contacts-empty" class="hidden only:table-row">
                    <td colspan="4" class="px-4 py-16 text-center">
                      <span class="icon-[tabler--users] mx-auto mb-3 block size-10 text-base-content/20" />
                      <p class="text-sm font-medium text-base-content/50">
                        {gettext("No contacts found.")}
                      </p>
                      <p class="mt-1 text-xs text-base-content/30">
                        {gettext("Try adjusting your search or filters.")}
                      </p>
                    </td>
                  </tr>
                  <tr
                    :for={{id, contact} <- @streams.contacts}
                    id={id}
                    class="group divide-x divide-base-content/8 transition-colors hover:bg-base-200/40"
                  >
                    <td class="relative w-64 px-4 py-3">
                      <% full_name = "#{contact.first_name} #{contact.last_name}" %>
                      <% display_name =
                        if String.length(full_name) > 30,
                          do: String.slice(full_name, 0, 29) <> "\u2026",
                          else: full_name %>
                      <div class="flex items-center gap-3 pr-8">
                        <%= if contact.avatar_id do %>
                          <img
                            id={"contact-avatar-#{contact.id}"}
                            src={~p"/uploads/avatar/#{contact.avatar_id}"}
                            alt=""
                            class="size-8 shrink-0 rounded-full bg-base-200 object-cover ring-1 ring-base-content/10"
                          />
                        <% else %>
                          <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary">
                            {String.first(contact.first_name || "?")}
                          </div>
                        <% end %>
                        <div class="min-w-0 flex-1">
                          <.link
                            navigate={~p"/contacts/#{contact}"}
                            data-full-name={full_name}
                            class="block truncate text-sm font-medium decoration-primary/60 underline-offset-2 transition-colors hover:text-primary hover:underline"
                          >
                            {display_name}
                          </.link>
                          <p
                            :if={contact.company}
                            class="mt-0.5 truncate text-xs text-base-content/60"
                          >
                            {contact.company.name}
                          </p>
                        </div>
                      </div>
                      <div
                        id={"row-menu-#{id}"}
                        phx-hook="RowMenu"
                        class="absolute right-3 inset-y-0 flex items-center"
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
                              patch={~p"/contacts/#{contact}/edit/inline"}
                              class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-base-200/60"
                            >
                              <.icon name="icon-[tabler--pencil]" class="size-3.5" />
                              {gettext("Edit")}
                            </.link>
                          </li>
                          <li>
                            <%= if is_nil(contact.archived_at) do %>
                              <.link
                                phx-click={JS.push("archive", value: %{id: contact.id})}
                                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-warning/10 hover:text-warning"
                              >
                                <.icon name="icon-[tabler--archive]" class="size-3.5" />
                                {gettext("Archive")}
                              </.link>
                            <% else %>
                              <.link
                                phx-click={JS.push("restore", value: %{id: contact.id})}
                                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-success/10 hover:text-success"
                              >
                                <.icon name="icon-[tabler--archive-off]" class="size-3.5" />
                                {gettext("Restore")}
                              </.link>
                            <% end %>
                          </li>
                          <li>
                            <.link
                              phx-click={JS.push("delete", value: %{id: contact.id})}
                              data-confirm={gettext("Are you sure?")}
                              class="danger-action flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-colors"
                            >
                              <.icon name="icon-[tabler--trash]" class="size-3.5" />
                              {gettext("Delete")}
                            </.link>
                          </li>
                        </ul>
                      </div>
                    </td>

                    <td class="px-4 py-3 text-sm text-base-content/60">{contact.email}</td>

                    <td class="px-4 py-3">
                      <span class={[
                        "inline-flex items-center gap-1.5 rounded-md border px-2.5 py-0.5 text-xs font-semibold",
                        status_pill_class(contact.status)
                      ]}>
                        <span class="size-1.5 shrink-0 rounded-full bg-current" />
                        {Phoenix.Naming.humanize(contact.status)}
                      </span>
                    </td>

                    <td class="px-4 py-3 text-sm text-base-content/60">
                      {Calendar.strftime(contact.inserted_at, "%b %-d, %Y")}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </.async_result>

        <%!-- Footer: count + pagination --%>
        <div
          :if={@contacts.ok? and !@contacts.loading}
          id="contacts-footer"
          class="mt-6 flex flex-wrap items-center justify-between gap-3"
        >
          <p class="text-sm text-base-content/50">
            <%= if @total == 0 do %>
              {gettext("No contacts found")}
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
                  <span class="flex h-8 w-8 items-center justify-center text-sm text-base-content/30 select-none">
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
        id="contact-modal"
        show
        on_cancel={hide_modal("contact-modal") |> JS.patch(~p"/contacts")}
      >
        <.live_component
          module={KonevoWeb.ContactsLive.FormComponent}
          id={if @contact && @contact.id, do: @contact.id, else: :new}
          title={if @live_action == :new, do: gettext("New Contact"), else: gettext("Edit Contact")}
          action={@live_action}
          contact={@contact}
          current_scope={@current_scope}
          patch={~p"/contacts"}
        />
      </.modal>
    </Layouts.app>
    """
  end

  attr :sort_by, :atom, required: true
  attr :sort_dir, :atom, required: true

  defp contacts_table_header(assigns) do
    ~H"""
    <colgroup>
      <col />
      <col class="w-64" />
      <col class="w-40" />
      <col class="w-44" />
    </colgroup>
    <thead>
      <tr class="divide-x divide-base-content/15 border-b border-secondary/35 bg-secondary/10">
        <th
          :for={
            {label, column} <- [
              {gettext("Name"), :name},
              {gettext("Email"), :email},
              {gettext("Status"), :status},
              {gettext("Date"), :inserted_at}
            ]
          }
          class="px-4 py-3 text-left"
        >
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
        </th>
      </tr>
    </thead>
    """
  end

  attr :active, :boolean, required: true
  attr :dir, :atom, required: true

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

  defp status_pill_class(:lead),
    do: "border-info/30 bg-info/12 text-info"

  defp status_pill_class(:prospect),
    do: "border-amber-500/30 bg-amber-500/10 text-amber-700"

  defp status_pill_class(:customer),
    do: "border-success/30 bg-success/12 text-success"

  defp status_pill_class(:churned),
    do: "border-error/30 bg-error/12 text-error"

  defp status_pill_class(_),
    do: "border-base-content/15 bg-base-200 text-base-content/60"

  defp status_dot_class(:lead), do: "bg-info"
  defp status_dot_class(:prospect), do: "bg-warning"
  defp status_dot_class(:customer), do: "bg-success"
  defp status_dot_class(:churned), do: "bg-error"
  defp status_dot_class(_), do: "bg-base-300"

  defp contact_initials(%{first_name: fn_, last_name: ln}) do
    [fn_, ln]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  defp contact_initials(_), do: "?"

  defp filled_url(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      url -> url
    end
  end

  defp filled_url(_value), do: nil

  defp status_avatar_class(:lead), do: "bg-info/15 text-info"
  defp status_avatar_class(:prospect), do: "bg-amber-500/15 text-amber-600"
  defp status_avatar_class(:customer), do: "bg-success/15 text-success"
  defp status_avatar_class(:churned), do: "bg-error/15 text-error"
  defp status_avatar_class(_), do: "bg-primary/10 text-primary"

  defp status_card_accent(:lead), do: "bg-gradient-to-r from-info/60 to-info/20"
  defp status_card_accent(:prospect), do: "bg-gradient-to-r from-amber-500/60 to-amber-500/20"
  defp status_card_accent(:customer), do: "bg-gradient-to-r from-success/60 to-success/20"
  defp status_card_accent(:churned), do: "bg-gradient-to-r from-error/60 to-error/20"
  defp status_card_accent(_), do: "bg-gradient-to-r from-base-content/20 to-base-content/5"
end
