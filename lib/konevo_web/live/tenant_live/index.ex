defmodule KonevoWeb.TenantLive.Index do
  use KonevoWeb, :live_view

  alias Konevo.Accounts
  alias Konevo.Accounts.Organization
  alias Phoenix.LiveView.AsyncResult

  @impl true
  def mount(_params, _session, socket) do
    if main_tenant_owner?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(:page_title, gettext("Tenants"))
       |> assign(:form, tenant_form())
       |> assign(:search, "")
       |> assign(:tenant_invitations, AsyncResult.loading())
       |> stream(:tenant_invitations, [])}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Not authorized"))
       |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    if connected?(socket) and main_tenant_owner?(socket.assigns.current_scope) do
      {:noreply, load_tenant_invitations(socket, Map.get(params, "search", ""))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate", %{"tenant" => params}, socket) do
    {:noreply, assign(socket, form: tenant_form(params))}
  end

  def handle_event("search", %{"q" => search}, socket) do
    {:noreply, push_patch(socket, to: tenant_index_path(search), replace: true)}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/tenants", replace: true)}
  end

  def handle_event("create", %{"tenant" => params}, socket) do
    scope = socket.assigns.current_scope

    case Accounts.create_tenant_invitation(scope, params, &tenant_invitation_url(socket, &1, &2)) do
      {:ok, %{invitation: invitation}} ->
        {:noreply,
         socket
         |> stream_insert(:tenant_invitations, invitation)
         |> assign(:form, tenant_form())
         |> put_flash(:success, gettext("Tenant created and invitation sent"))
         |> push_patch(to: ~p"/tenants")}

      {:error, _operation, %Ecto.Changeset{} = changeset, _changes} ->
        {:noreply, assign(socket, form: tenant_form(params, form_errors(changeset)))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Not authorized"))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, gettext("Could not create the tenant. Please try again"))}
    end
  end

  def handle_event("archive_tenant", %{"id" => id}, socket) do
    update_tenant_archive_state(
      socket,
      id,
      &Accounts.archive_tenant/2,
      gettext("Tenant archived")
    )
  end

  def handle_event("restore_tenant", %{"id" => id}, socket) do
    update_tenant_archive_state(
      socket,
      id,
      &Accounts.restore_tenant/2,
      gettext("Tenant restored")
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.page title={@page_title}>
        <:actions>
          <.button
            patch={~p"/tenants/new"}
            id="new-tenant-button"
            class="btn btn-primary btn-sm gap-1.5"
          >
            <.icon name="icon-[tabler--plus]" class="size-4" />
            {gettext("Add tenant")}
          </.button>
        </:actions>

        <div class="mb-4 flex flex-wrap items-center gap-2">
          <div class="relative w-72 shrink-0">
            <.icon
              name="icon-[tabler--search]"
              class="pointer-events-none absolute left-2.5 top-1/2 z-10 size-3.5 -translate-y-1/2 text-base-content/40"
            />
            <form phx-change="search" phx-submit="search" id="tenant-search-form">
              <input
                type="text"
                name="q"
                value={@search}
                placeholder={gettext("Search tenants or owners")}
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
        </div>

        <.async_result :let={_stream_ready?} assign={@tenant_invitations}>
          <:loading>
            <div
              id="tenant-table-loading"
              class="overflow-x-auto rounded-xl border border-base-content/20 bg-base-100"
              aria-busy="true"
              aria-label={gettext("Loading tenants")}
            >
              <table class="table w-full min-w-[50rem] table-fixed">
                <.tenant_table_header />
                <tbody class="divide-y divide-base-content/8">
                  <tr
                    :for={row <- 1..5}
                    id={"tenant-skeleton-#{row}"}
                    class="divide-x divide-base-content/8"
                  >
                    <td class="px-4 py-3"><div class="skeleton h-4 w-40 rounded-md" /></td>
                    <td class="px-4 py-3"><div class="skeleton h-4 w-28 rounded-md" /></td>
                    <td class="px-4 py-3"><div class="skeleton h-4 w-48 rounded-md" /></td>
                    <td class="px-4 py-3"><div class="skeleton h-7 w-20 rounded-md" /></td>
                    <td class="px-4 py-3"><div class="skeleton h-4 w-24 rounded-md" /></td>
                  </tr>
                </tbody>
              </table>
            </div>
          </:loading>
          <:failed :let={_reason}>
            <div
              id="tenant-load-error"
              class="rounded-xl border border-error/30 bg-error/5 px-6 py-12 text-center"
              role="alert"
            >
              <.icon name="icon-[tabler--alert-circle]" class="mx-auto mb-3 size-8 text-error" />
              <p class="font-medium text-error">{gettext("Failed to load tenants")}</p>
            </div>
          </:failed>

          <div
            id="tenant-table"
            class="overflow-x-auto rounded-xl border border-base-content/20 bg-base-100"
          >
            <table class="table w-full min-w-[50rem] table-fixed">
              <.tenant_table_header />
              <tbody
                id="tenant-invitations"
                phx-update="stream"
                class="divide-y divide-base-content/8"
              >
                <tr
                  :if={!@tenant_invitations.loading}
                  id="tenant-invitations-empty"
                  class="hidden only:table-row"
                >
                  <td colspan="5" class="px-4 py-16 text-center">
                    <.icon
                      name="icon-[tabler--buildings]"
                      class="mx-auto mb-3 block size-10 text-base-content/20"
                    />
                    <p class="text-sm font-medium text-base-content/50">
                      {gettext("No tenants found.")}
                    </p>
                    <p class="mt-1 text-xs text-base-content/30">
                      {gettext("Try adjusting your search.")}
                    </p>
                  </td>
                </tr>
                <tr
                  :for={{id, invitation} <- @streams.tenant_invitations}
                  id={id}
                  class="group divide-x divide-base-content/8 transition-colors hover:bg-base-200/40"
                >
                  <td class="relative px-4 py-3">
                    <p class="truncate pr-9 text-sm font-medium text-base-content">
                      {invitation.organization.name}
                    </p>
                    <.tenant_actions invitation={invitation} />
                  </td>
                  <td class="px-4 py-3">
                    <p
                      id={"tenant-slug-#{invitation.id}"}
                      class="truncate text-sm text-base-content/70"
                    >
                      {invitation.organization.slug}
                    </p>
                  </td>
                  <td class="px-4 py-3 text-sm text-base-content/70">{invitation.email}</td>
                  <td class="px-4 py-3">
                    <.tenant_status_pill invitation={invitation} />
                  </td>
                  <td class="px-4 py-3 text-sm text-base-content/60">
                    {format_date(invitation.inserted_at)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.async_result>
      </Layouts.page>

      <.modal
        :if={@live_action == :new}
        id="tenant-modal"
        show
        on_cancel={hide_modal("tenant-modal") |> JS.patch(~p"/tenants")}
      >
        <div class="p-1 sm:p-2">
          <div class="mb-5">
            <p class="text-sm font-semibold text-primary">{gettext("New tenant")}</p>
            <h2 class="mt-1 text-xl font-semibold tracking-tight text-base-content">
              {gettext("Invite a workspace owner")}
            </h2>
            <p class="mt-2 text-sm leading-6 text-base-content/60">
              {gettext("They receive a secure link that expires in exactly three days.")}
            </p>
          </div>

          <.form
            for={@form}
            id="tenant-create-form"
            phx-change="validate"
            phx-submit="create"
            class="space-y-4"
          >
            <.input field={@form[:name]} type="text" label={gettext("Organization name")} required />
            <.input
              field={@form[:slug]}
              type="text"
              label={gettext("Tenant slug")}
              placeholder="acme"
              required
            />
            <.input
              field={@form[:email]}
              type="email"
              label={gettext("Owner email")}
              autocomplete="email"
              required
            />
            <div class="flex justify-end gap-2 pt-2">
              <.button patch={~p"/tenants"} class="btn btn-ghost btn-sm" type="button">
                {gettext("Cancel")}
              </.button>
              <.button
                id="tenant-create-button"
                type="submit"
                class="btn btn-primary btn-sm gap-1.5 transition-transform hover:-translate-y-0.5"
                phx-disable-with={gettext("Sending invitation...")}
              >
                <.icon name="icon-[tabler--send]" class="size-4" />
                {gettext("Create tenant")}
              </.button>
            </div>
          </.form>
        </div>
      </.modal>
    </Layouts.app>
    """
  end

  defp main_tenant_owner?(%{org: %Organization{} = org, membership: %{role: :owner}}) do
    org.slug == Application.fetch_env!(:konevo, :default_tenant_slug)
  end

  defp main_tenant_owner?(_scope), do: false

  defp load_tenant_invitations(socket, search) do
    search = String.trim(search)

    socket
    |> assign(:search, search)
    |> cancel_async(:tenant_invitations)
    |> stream_async(:tenant_invitations, fn ->
      {:ok, Accounts.list_tenant_invitations(search: search), reset: true}
    end)
  end

  defp tenant_index_path(""), do: ~p"/tenants"
  defp tenant_index_path(search), do: ~p"/tenants?#{[search: search]}"

  defp tenant_form(params \\ %{}, errors \\ []) do
    params = Map.merge(%{"name" => "", "slug" => "", "email" => ""}, params)
    to_form(params, as: "tenant", errors: errors)
  end

  defp form_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &{field, {&1, []}}) end)
  end

  defp tenant_invitation_url(socket, organization, token) do
    endpoint_url = KonevoWeb.Endpoint.config(:url)
    uri = socket.host_uri || URI.parse(KonevoWeb.Endpoint.url())
    scheme = endpoint_url[:scheme] || uri.scheme || "http"
    base_host = endpoint_url[:host]
    port = endpoint_url[:port] || uri.port
    port_suffix = if port in [80, 443, nil], do: "", else: ":#{port}"

    "#{scheme}://#{organization.slug}.#{base_host}#{port_suffix}/tenant-invitations/#{token}"
  end

  defp update_tenant_archive_state(socket, id, operation, success_message) do
    case operation.(socket.assigns.current_scope, id) do
      {:ok, invitation} ->
        {:noreply,
         socket
         |> stream_insert(:tenant_invitations, invitation)
         |> put_flash(:success, success_message)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Not authorized"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update the tenant"))}
    end
  end

  attr(:invitation, :any, required: true)

  defp tenant_actions(assigns) do
    ~H"""
    <div
      id={"tenant-row-menu-#{@invitation.id}"}
      phx-hook="RowMenu"
      class="absolute inset-y-0 right-3 flex items-center"
    >
      <button
        type="button"
        data-toggle
        class="flex size-7 cursor-pointer items-center justify-center rounded-md text-base-content/40 transition-colors hover:bg-base-content/10 hover:text-base-content"
        aria-label={gettext("Tenant actions")}
      >
        <.icon name="icon-[tabler--dots-vertical]" class="size-4" />
      </button>
      <ul
        data-panel
        class="row-menu-closed z-50 w-44 overflow-hidden rounded-lg border border-base-content/15 bg-base-100 p-1 shadow-xl shadow-base-content/10"
        role="menu"
      >
        <li :if={is_nil(@invitation.organization.archived_at)}>
          <button
            type="button"
            phx-click="archive_tenant"
            phx-value-id={@invitation.id}
            data-confirm={
              gettext("Archive this tenant? Its users will no longer be able to access it.")
            }
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-base-content/70 transition-colors hover:bg-warning/10 hover:text-warning"
            role="menuitem"
          >
            <.icon name="icon-[tabler--archive]" class="size-3.5" />
            {gettext("Archive")}
          </button>
        </li>
        <li :if={!is_nil(@invitation.organization.archived_at)}>
          <button
            type="button"
            phx-click="restore_tenant"
            phx-value-id={@invitation.id}
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-base-content/70 transition-colors hover:bg-success/10 hover:text-success"
            role="menuitem"
          >
            <.icon name="icon-[tabler--archive-off]" class="size-3.5" />
            {gettext("Restore")}
          </button>
        </li>
      </ul>
    </div>
    """
  end

  attr(:invitation, :any, required: true)

  defp tenant_status_pill(assigns) do
    {color, icon, label} = tenant_status_details(assigns.invitation)
    assigns = assign(assigns, color: color, icon: icon, label: label)

    ~H"""
    <span
      id={"tenant-status-#{@invitation.id}"}
      class="inline-flex items-center gap-1 rounded-md border px-2.5 py-1 text-xs font-medium"
      style={tenant_status_pill_style(@color)}
    >
      <.icon name={@icon} class="size-3.5 shrink-0" />
      {@label}
    </span>
    """
  end

  defp tenant_status_details(%{organization: %{archived_at: archived_at}})
       when not is_nil(archived_at),
       do: {"#94a3b8", "icon-[tabler--archive]", gettext("Archived")}

  defp tenant_status_details(%{accepted_at: accepted_at}) when not is_nil(accepted_at),
    do: {"#10b981", "icon-[tabler--circle-check-filled]", gettext("Active")}

  defp tenant_status_details(_invitation),
    do: {"#f59e0b", "icon-[tabler--clock-hour-4]", gettext("Pending")}

  defp tenant_status_pill_style(color) do
    [
      "background-color: color-mix(in srgb, #{color} 14%, transparent)",
      "border-color: color-mix(in srgb, #{color} 35%, transparent)",
      "color: #{color}"
    ]
    |> Enum.join("; ")
  end

  defp format_date(%DateTime{} = date), do: Calendar.strftime(date, "%d %b %Y")
  defp format_date(_date), do: "—"

  defp tenant_table_header(assigns) do
    ~H"""
    <colgroup>
      <col />
      <col class="w-40" />
      <col class="w-72" />
      <col class="w-32" />
      <col class="w-36" />
    </colgroup>
    <thead>
      <tr class="divide-x divide-base-content/15 border-b border-secondary/35 bg-secondary/10">
        <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-base-content/60">
          {gettext("Tenant")}
        </th>
        <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-base-content/60">
          {gettext("Slug")}
        </th>
        <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-base-content/60">
          {gettext("Owner")}
        </th>
        <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-base-content/60">
          {gettext("Status")}
        </th>
        <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-base-content/60">
          {gettext("Created")}
        </th>
      </tr>
    </thead>
    """
  end
end
