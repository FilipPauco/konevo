defmodule KonevoWeb.TeamLive.Index do
  use KonevoWeb, :live_view

  alias Konevo.Accounts
  alias Konevo.Accounts.Membership
  alias Konevo.Permissions

  @per_page 25
  @sortable_columns ~w(email role inserted_at)

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, gettext("Team"))
     |> assign(:invite_form, nil)
     |> assign(:can_manage, can_manage?(scope))
     |> assign(:search, "")
     |> assign(:archive_filter, :active)
     |> assign(:sort_by, :email)
     |> assign(:sort_dir, :asc)
     |> assign(:page, 1)
     |> assign(:total, 0)
     |> assign(:members_request_ref, nil)
     |> stream(:members, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, load_members(socket, params)}
  end

  defp load_members(socket, params) do
    %{
      search: search,
      archive_filter: archive_filter,
      sort_by: sort_by,
      sort_dir: sort_dir,
      page: page
    } =
      parse_filter_params(params)

    scope = socket.assigns.current_scope
    live_view = self()
    request_ref = make_ref()

    opts = [
      search: search,
      archive_filter: archive_filter,
      sort_by: sort_by,
      sort_dir: sort_dir,
      page: page,
      per_page: @per_page
    ]

    socket
    |> assign(:search, search)
    |> assign(:archive_filter, archive_filter)
    |> assign(:sort_by, sort_by)
    |> assign(:sort_dir, sort_dir)
    |> assign(:page, page)
    |> assign(:members_request_ref, request_ref)
    |> cancel_async(:members)
    |> stream_async(:members, fn ->
      {members, total} = Accounts.list_members(scope.org, opts)
      send(live_view, {:members_total, request_ref, total})
      {:ok, members, reset: true}
    end)
  end

  defp parse_filter_params(params) do
    %{
      search: Map.get(params, "search", ""),
      archive_filter: parse_archive_filter(Map.get(params, "archived", "")),
      sort_by: parse_sort_by(Map.get(params, "sort_by", "")),
      sort_dir: parse_sort_dir(Map.get(params, "sort_dir", "")),
      page: parse_page(Map.get(params, "page", ""))
    }
  end

  defp parse_sort_by(col) when col in @sortable_columns,
    do: String.to_existing_atom(col)

  defp parse_sort_by(_), do: :email

  defp parse_sort_dir("desc"), do: :desc
  defp parse_sort_dir(_), do: :asc

  defp parse_page(str) when is_binary(str) and str != "" do
    case Integer.parse(str) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  defp parse_archive_filter("archived"), do: :archived
  defp parse_archive_filter("all"), do: :all
  defp parse_archive_filter(_), do: :active

  @impl true
  def handle_info({:members_total, request_ref, total}, socket) do
    if request_ref == socket.assigns.members_request_ref do
      {:noreply, assign(socket, :total, total)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: build_url(socket, %{search: q, page: 1}), replace: true)}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, push_patch(socket, to: build_url(socket, %{search: "", page: 1}), replace: true)}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: build_url(socket, %{search: "", archive_filter: :active, page: 1}),
       replace: true
     )}
  end

  def handle_event("set_archive_filter", %{"filter" => filter}, socket) do
    archive_filter = parse_archive_filter(filter)

    {:noreply,
     push_patch(socket, to: build_url(socket, %{archive_filter: archive_filter, page: 1}))}
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

  def handle_event("open_invite", _params, socket) do
    if can_manage?(socket.assigns.current_scope) do
      form = to_form(%{"email" => "", "role" => "member"}, as: "invite")
      {:noreply, assign(socket, :invite_form, form)}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  def handle_event("close_invite", _params, socket) do
    {:noreply, assign(socket, :invite_form, nil)}
  end

  def handle_event("validate_invite", %{"invite" => params}, socket) do
    if can_manage?(socket.assigns.current_scope) do
      form = to_form(params, as: "invite")
      {:noreply, assign(socket, :invite_form, form)}
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  def handle_event("invite", %{"invite" => %{"email" => email, "role" => role}}, socket) do
    scope = socket.assigns.current_scope

    with true <- can_manage?(scope),
         {:ok, role_atom} <- parse_role(role) do
      url_fun = fn token ->
        build_invite_base_url(socket) <> "/users/log-in/#{token}"
      end

      case Accounts.invite_member(scope.org, email, role_atom, url_fun) do
        {:ok, membership} ->
          {:noreply,
           socket
           |> stream_insert(:members, membership)
           |> update(:total, &(&1 + 1))
           |> assign(:invite_form, nil)
           |> put_flash(:success, gettext("Invitation sent to %{email}", email: email))}

        {:error, :already_member} ->
          {:noreply,
           put_flash(socket, :error, gettext("%{email} is already a member", email: email))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not send invite. Try again"))}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  def handle_event("change_role", %{"id" => id, "role" => role}, socket) do
    scope = socket.assigns.current_scope

    with true <- can_manage?(scope),
         {:ok, _role_atom} <- parse_role(role) do
      membership = Accounts.get_membership!(scope.org, id)

      case Accounts.update_membership(membership, %{role: role}) do
        {:ok, updated} ->
          {:noreply, stream_insert(socket, :members, updated)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update role"))}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    if can_manage?(scope) do
      membership = Accounts.get_membership!(scope.org, id)

      if membership.role == :owner do
        {:noreply, put_flash(socket, :error, gettext("Cannot remove the owner"))}
      else
        {:ok, _deleted} = Accounts.delete_membership(membership)

        {:noreply,
         socket
         |> update(:total, &max(&1 - 1, 0))
         |> stream_delete(:members, membership)}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  def handle_event("archive_member", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    if can_manage?(scope) do
      membership = Accounts.get_membership!(scope.org, id)

      case Accounts.archive_membership(scope.user, membership) do
        {:ok, archived} ->
          {:noreply,
           socket
           |> put_flash(:success, gettext("Member archived"))
           |> apply_member_archive_change(membership, archived)}

        {:error, :cannot_archive_owner} ->
          {:noreply, put_flash(socket, :error, gettext("Cannot archive the owner"))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not archive member"))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  def handle_event("restore_member", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    if can_manage?(scope) do
      membership = Accounts.get_membership!(scope.org, id)

      case Accounts.restore_membership(membership) do
        {:ok, restored} ->
          {:noreply,
           socket
           |> put_flash(:success, gettext("Member restored"))
           |> apply_member_archive_change(membership, restored)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not restore member"))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
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
      |> assign(:filters_active?, assigns.search != "" or assigns.archive_filter != :active)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.page title={@page_title}>
        <:actions :if={@can_manage}>
          <.button
            id="invite-member-button"
            phx-click="open_invite"
            disabled
            title={gettext("Member invitations are not available yet")}
            class="btn btn-primary btn-sm gap-1.5 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <.icon name="icon-[tabler--user-plus]" class="size-4" />
            {gettext("Invite member")}
          </.button>
        </:actions>

        <div class="mb-4 flex flex-wrap items-center gap-2">
          <div class="relative w-full shrink-0 sm:w-64">
            <.icon
              name="icon-[tabler--search]"
              class="pointer-events-none absolute left-2.5 top-1/2 z-10 size-3.5 -translate-y-1/2 text-base-content/40"
            />
            <form phx-change="search" phx-submit="search" id="team-search-form">
              <input
                type="text"
                name="q"
                value={@search}
                placeholder={gettext("Search by email or role")}
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

          <div class="hidden sm:block">
            <.archive_filter_dropdown
              id="team-archive-filter"
              selected={@archive_filter}
              options={archive_filter_options()}
            />
          </div>

          <div class="flex items-center gap-2 sm:hidden">
            <button
              type="button"
              class={[
                "btn btn-sm gap-1.5 border select-none",
                if(@archive_filter != :active,
                  do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                  else:
                    "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                )
              ]}
              phx-click={
                JS.toggle(
                  to: "#team-filter-panel",
                  display: "flex",
                  in:
                    {"transition ease-out duration-200", "opacity-0 -translate-y-1",
                     "opacity-100 translate-y-0"},
                  out:
                    {"transition ease-in duration-150", "opacity-100 translate-y-0",
                     "opacity-0 -translate-y-1"}
                )
                |> JS.toggle_class("rotate-180", to: "#team-filter-chevron")
              }
            >
              <.icon name="icon-[tabler--adjustments-horizontal]" class="size-3.5" />
              {gettext("Filters")}
              <span
                :if={@archive_filter != :active}
                class="flex size-4 items-center justify-center rounded-full bg-primary text-[10px] font-bold text-primary-content"
              >
                1
              </span>
              <.icon
                id="team-filter-chevron"
                name="icon-[tabler--chevron-down]"
                class="size-3.5 opacity-50 transition-transform duration-200"
              />
            </button>
            <button
              :if={@filters_active?}
              id="team-clear-filters-mobile"
              phx-click="clear_filters"
              type="button"
              aria-label={gettext("Clear filters")}
              class="btn btn-sm btn-square border border-base-content/20 bg-base-100 text-base-content/60 transition-all hover:border-base-content/30 hover:text-base-content"
            >
              <.icon name="icon-[tabler--x]" class="size-3.5" />
            </button>
          </div>

          <div
            id="team-filter-panel"
            class="hidden w-full flex-wrap items-center gap-2 rounded-xl border border-secondary/35 bg-secondary/10 p-3 sm:hidden"
          >
            <.archive_filter_dropdown
              id="team-archive-filter-mobile"
              selected={@archive_filter}
              options={archive_filter_options()}
            />
          </div>

          <div :if={@filters_active?} class="hidden border-l border-base-content/15 pl-2 sm:block">
            <button
              id="team-clear-filters"
              phx-click="clear_filters"
              type="button"
              class="btn btn-sm gap-1.5 border border-base-content/20 bg-base-100 text-base-content/60 transition-all hover:border-base-content/30 hover:text-base-content"
            >
              <.icon name="icon-[tabler--x]" class="size-3" />
              {gettext("Clear filters")}
            </button>
          </div>
        </div>

        <.async_result :let={_stream_ready?} assign={@members}>
          <:loading>
            <div
              id="team-loading"
              class="mobile-data-table-container overflow-x-auto rounded-xl border border-base-content/20 bg-base-100"
              aria-busy="true"
              aria-label={gettext("Loading team members")}
            >
              <table class="mobile-data-table table w-full min-w-[44rem] table-fixed">
                <.members_table_header
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
                <tbody class="divide-y divide-base-content/8">
                  <tr
                    :for={row <- 1..6}
                    id={"member-skeleton-#{row}"}
                    class="mobile-data-skeleton divide-x divide-base-content/8"
                  >
                    <td class="px-4 py-3">
                      <div class="flex items-center gap-3">
                        <div class="skeleton size-8 shrink-0 rounded-full" />
                        <div class="skeleton h-3.5 w-40 rounded-md" />
                      </div>
                    </td>
                    <td class="px-4 py-3">
                      <div class="skeleton h-7 w-24 rounded-md" />
                    </td>
                    <td class="px-4 py-3">
                      <div class="skeleton h-3.5 w-24 rounded-md" />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </:loading>
          <:failed :let={_reason}>
            <div
              id="team-load-error"
              class="rounded-xl border border-error/30 bg-error/5 px-6 py-12 text-center"
              role="alert"
            >
              <.icon name="icon-[tabler--alert-circle]" class="mx-auto mb-3 size-8 text-error" />
              <p class="font-medium text-error">{gettext("Failed to load team members")}</p>
              <p class="mt-1 text-sm text-base-content/50">
                {gettext("Please refresh the page and try again.")}
              </p>
            </div>
          </:failed>

          <div
            id="team-table"
            class="mobile-data-table-container overflow-x-auto rounded-xl border border-base-content/20 bg-base-100"
          >
            <table class="mobile-data-table table w-full min-w-[44rem] table-fixed">
              <.members_table_header sort_by={@sort_by} sort_dir={@sort_dir} />

              <tbody id="members" phx-update="stream" class="divide-y divide-base-content/8">
                <tr
                  :if={!@members.loading}
                  id="members-empty"
                  class="mobile-data-empty hidden only:table-row"
                >
                  <td colspan="3" class="px-4 py-16 text-center">
                    <.icon
                      name="icon-[tabler--users]"
                      class="mx-auto mb-3 block size-10 text-base-content/20"
                    />
                    <p class="text-sm font-medium text-base-content/50">
                      {gettext("No team members found.")}
                    </p>
                    <p class="mt-1 text-xs text-base-content/30">
                      {gettext("Try adjusting your search.")}
                    </p>
                  </td>
                </tr>

                <tr
                  :for={{id, membership} <- @streams.members}
                  id={id}
                  class="mobile-data-card group divide-x divide-base-content/8 transition-colors hover:bg-base-200/40"
                >
                  <td class="mobile-data-title relative px-4 py-3">
                    <div class="flex min-w-0 items-center gap-3 pr-8">
                      <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary">
                        {avatar_initials(membership.user.email)}
                      </div>
                      <div class="min-w-0">
                        <p class="truncate text-sm font-medium text-base-content">
                          {membership.user.email}
                        </p>
                      </div>
                    </div>
                    <div
                      :if={@can_manage and membership.role != :owner}
                      id={"member-row-menu-#{id}"}
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
                          <%= if is_nil(membership.archived_at) do %>
                            <button
                              type="button"
                              phx-click="archive_member"
                              phx-value-id={membership.id}
                              class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-base-content/70 transition-colors hover:bg-warning/10 hover:text-warning"
                              role="menuitem"
                            >
                              <.icon name="icon-[tabler--archive]" class="size-3.5" />
                              {gettext("Archive")}
                            </button>
                          <% else %>
                            <button
                              type="button"
                              phx-click="restore_member"
                              phx-value-id={membership.id}
                              class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-base-content/70 transition-colors hover:bg-success/10 hover:text-success"
                              role="menuitem"
                            >
                              <.icon name="icon-[tabler--archive-off]" class="size-3.5" />
                              {gettext("Restore")}
                            </button>
                          <% end %>
                        </li>
                        <li>
                          <button
                            type="button"
                            phx-click="remove_member"
                            phx-value-id={membership.id}
                            data-confirm={gettext("Remove this member from the workspace?")}
                            class="danger-action flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium transition-colors"
                            role="menuitem"
                          >
                            <.icon name="icon-[tabler--user-minus]" class="size-3.5" />
                            {gettext("Remove")}
                          </button>
                        </li>
                      </ul>
                    </div>
                  </td>

                  <td class="mobile-data-field mobile-data-field--primary px-4 py-3">
                    <span class="mobile-data-field-label">{gettext("Role")}</span>
                    <%= if @can_manage and membership.role != :owner do %>
                      <form
                        id={"member-role-form-#{membership.id}"}
                        phx-change="change_role"
                        phx-value-id={membership.id}
                      >
                        <select
                          name="role"
                          class="select select-bordered select-sm w-32"
                          aria-label={gettext("Change role")}
                        >
                          <%= for {label, value} <- role_options() do %>
                            <option value={value} selected={to_string(membership.role) == value}>
                              {label}
                            </option>
                          <% end %>
                        </select>
                      </form>
                    <% else %>
                      <.role_badge role={membership.role} />
                    <% end %>
                  </td>

                  <td class="mobile-data-field mobile-data-field--end px-4 py-3 text-sm text-base-content/60">
                    <span class="mobile-data-field-label">{gettext("Joined")}</span>
                    <span>{Calendar.strftime(membership.inserted_at, "%b %-d, %Y")}</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.async_result>

        <div
          :if={@members.ok? and !@members.loading and @total > 0}
          id="team-footer"
          class="mt-6 flex flex-wrap items-center justify-between gap-3"
        >
          <p class="text-sm text-base-content/50">
            {gettext("Showing %{from}-%{to} of %{total}",
              from: @page_from,
              to: @page_to,
              total: @total
            )}
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
                  <.icon name="icon-[tabler--chevron-left]" class="size-4" />
                </button>
              </li>

              <li :for={n <- @page_numbers}>
                <%= if n == :gap do %>
                  <span class="flex h-8 w-8 select-none items-center justify-center text-sm text-base-content/30">
                    ...
                  </span>
                <% else %>
                  <button
                    phx-click="page"
                    phx-value-n={n}
                    aria-current={if(n == @page, do: "page")}
                    class={[
                      "flex h-8 w-8 select-none items-center justify-center rounded-lg text-sm font-medium transition-all",
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
                  <.icon name="icon-[tabler--chevron-right]" class="size-4" />
                </button>
              </li>
            </ul>
          </nav>
        </div>

        <div
          :if={@invite_form}
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-sm"
        >
          <div class="w-full max-w-md rounded-xl bg-base-100 p-6 shadow-xl">
            <div class="mb-5 flex items-start justify-between">
              <div class="flex items-center gap-3">
                <div class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary/10">
                  <.icon name="icon-[tabler--user-plus]" class="size-5 text-primary" />
                </div>

                <div>
                  <h2 class="text-base font-semibold text-base-content">
                    {gettext("Invite a member")}
                  </h2>

                  <p class="text-xs text-base-content/50">
                    {gettext("They will receive a magic link to join.")}
                  </p>
                </div>
              </div>

              <button
                type="button"
                phx-click="close_invite"
                class="btn btn-ghost btn-sm btn-circle"
                aria-label={gettext("Close")}
              >
                <.icon name="icon-[tabler--x]" class="size-4" />
              </button>
            </div>

            <.form
              for={@invite_form}
              id="invite-form"
              phx-submit="invite"
              phx-change="validate_invite"
            >
              <.input
                field={@invite_form[:email]}
                type="email"
                label={gettext("Email address")}
                placeholder="colleague@company.com"
                required
                phx-mounted={JS.focus()}
              />
              <.input
                field={@invite_form[:role]}
                type="select"
                label={gettext("Role")}
                options={role_options()}
              />
              <div class="mt-5 flex justify-end gap-2">
                <.button type="button" phx-click="close_invite" class="btn btn-ghost btn-sm">
                  {gettext("Cancel")}
                </.button>
                <.button
                  type="submit"
                  phx-disable-with={gettext("Sending...")}
                  class="btn btn-primary btn-sm"
                >
                  {gettext("Send invite")}
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </Layouts.page>
    </Layouts.app>
    """
  end

  defp build_url(socket, overrides) do
    search = Map.get(overrides, :search, socket.assigns.search)
    archive_filter = Map.get(overrides, :archive_filter, socket.assigns.archive_filter)
    sort_by = Map.get(overrides, :sort_by, socket.assigns.sort_by)
    sort_dir = Map.get(overrides, :sort_dir, socket.assigns.sort_dir)
    page = Map.get(overrides, :page, socket.assigns.page)

    params =
      []
      |> push_param("search", search, "")
      |> push_param("archived", archive_filter_param(archive_filter), "active")
      |> push_param("sort_by", to_string(sort_by), "email")
      |> push_param("sort_dir", to_string(sort_dir), "asc")
      |> push_param("page", to_string(page), "1")
      |> Map.new()

    if map_size(params) == 0, do: ~p"/team", else: ~p"/team?#{params}"
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

  defp apply_member_archive_change(socket, old_membership, updated_membership) do
    case socket.assigns.archive_filter do
      :all ->
        stream_insert(socket, :members, updated_membership)

      _ ->
        socket
        |> update(:total, &max(&1 - 1, 0))
        |> stream_delete(:members, old_membership)
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

  defp parse_role(role) when is_binary(role) do
    role_atom = String.to_existing_atom(role)

    if role_atom in Membership.roles() do
      {:ok, role_atom}
    else
      {:error, :invalid_role}
    end
  rescue
    ArgumentError -> {:error, :invalid_role}
  end

  defp can_manage?(scope) do
    scope.org != nil and
      Permissions.has_role?(scope.user, scope.org, :admin)
  end

  defp build_invite_base_url(socket) do
    uri = socket.host_uri

    if uri do
      port_str = if uri.port in [80, 443, nil], do: "", else: ":#{uri.port}"
      "#{uri.scheme}://#{uri.host}#{port_str}"
    else
      KonevoWeb.Endpoint.url()
    end
  end

  defp role_options do
    [
      {role_label(:admin), "admin"},
      {role_label(:member), "member"},
      {role_label(:viewer), "viewer"}
    ]
  end

  defp avatar_initials(email) do
    email |> String.upcase() |> String.first()
  end

  defp role_label(:owner), do: gettext("Owner")
  defp role_label(:admin), do: gettext("Admin")
  defp role_label(:member), do: gettext("Member")
  defp role_label(:viewer), do: gettext("Viewer")

  attr :sort_by, :atom, required: true
  attr :sort_dir, :atom, required: true

  defp members_table_header(assigns) do
    ~H"""
    <colgroup>
      <col />
      <col class="w-44" />
      <col class="w-44" />
    </colgroup>
    <thead>
      <tr class="divide-x divide-base-content/15 border-b border-secondary/35 bg-secondary/10">
        <th
          :for={
            {label, column} <- [
              {gettext("Member"), :email},
              {gettext("Role"), :role},
              {gettext("Joined"), :inserted_at}
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
        <.icon name="icon-[tabler--arrow-up]" class="size-3 text-primary" />
      <% @active and @dir == :desc -> %>
        <.icon name="icon-[tabler--arrow-down]" class="size-3 text-primary" />
      <% true -> %>
        <.icon name="icon-[tabler--arrows-sort]" class="size-3 opacity-30" />
    <% end %>
    """
  end

  attr :role, :atom, required: true

  defp role_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-md px-2.5 py-0.5 text-xs font-medium",
      case @role do
        :owner -> "bg-primary/10 text-primary"
        :admin -> "bg-warning/10 text-warning"
        :member -> "bg-neutral/10 text-neutral"
        :viewer -> "bg-base-content/10 text-base-content/60"
      end
    ]}>
      <.icon name={role_icon(@role)} class="size-3" />
      {role_label(@role)}
    </span>
    """
  end

  defp role_icon(:owner), do: "icon-[tabler--crown]"
  defp role_icon(:admin), do: "icon-[tabler--shield-check]"
  defp role_icon(:member), do: "icon-[tabler--user]"
  defp role_icon(:viewer), do: "icon-[tabler--eye]"
end
