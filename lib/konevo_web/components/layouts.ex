defmodule KonevoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use KonevoWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates("layouts/*")

  @doc """
  Renders the authenticated app shell with fixed sidebar, topbar, and scrollable content area.

  ## Examples

      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <Layouts.page title="Inbox">
          Content here
        </Layouts.page>
      </Layouts.app>

  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")

  attr(:current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"
  )

  attr(:current_path, :string, default: nil, doc: "the current URL path for nav highlighting")

  slot(:inner_block, required: true)

  def app(assigns) do
    ~H"""
    <div class="flex h-screen overflow-hidden bg-base-200">
      <%!-- Mobile backdrop: shown when sidebar is open on small screens --%>
      <div
        id="sidebar-backdrop"
        class="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm hidden lg:hidden"
        phx-click={
          JS.remove_class("is-open", to: "#sidebar")
          |> JS.add_class("hidden", to: "#sidebar-backdrop")
          |> JS.remove_class("hidden", to: "#mobile-menu-open-icon")
          |> JS.add_class("hidden", to: "#mobile-menu-close-icon")
          |> JS.set_attribute({"aria-expanded", "false"}, to: "#mobile-menu-toggle")
          |> JS.set_attribute({"aria-label", gettext("Open menu")}, to: "#mobile-menu-toggle")
        }
      />
      <.sidebar current_path={@current_path} current_scope={@current_scope} />
      <div class="flex min-h-0 flex-1 flex-col overflow-hidden">
        <.topbar current_scope={@current_scope} />
        <main class="app-scroll-container min-h-0 flex-1 overflow-y-auto">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    <.flash_group flash={@flash} />
    <.unsaved_changes_modal />
    """
  end

  defp unsaved_changes_modal(assigns) do
    ~H"""
    <%!-- Backdrop --%>
    <div
      id="unsaved-changes-modal-backdrop"
      data-unsaved-backdrop
      class="fixed inset-0 z-69 hidden bg-black/50 backdrop-blur-sm"
      aria-hidden="true"
    />
    <%!-- Panel --%>
    <div
      id="unsaved-changes-modal"
      data-unsaved-modal
      class="fixed inset-0 z-70 hidden overflow-y-auto"
      role="dialog"
      aria-modal="true"
      aria-labelledby="unsaved-changes-title"
    >
      <div class="flex min-h-full items-center justify-center p-4">
        <div
          id="unsaved-changes-modal-content"
          class="relative w-full max-w-md rounded-2xl bg-base-100 p-6 shadow-xl"
        >
          <%!-- Close button --%>
          <button
            type="button"
            class="btn btn-sm btn-square btn-ghost absolute right-3 top-3"
            data-unsaved-stay
            aria-label={gettext("Close")}
          >
            <.icon name="icon-[tabler--x]" class="size-4" />
          </button>

          <div class="flex items-start gap-4">
            <div class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-error/10 text-error">
              <span class="icon-[tabler--alert-triangle] size-5" />
            </div>
            <div class="min-w-0 flex-1 pr-6">
              <h2 id="unsaved-changes-title" class="text-base font-semibold text-base-content">
                {gettext("Discard unsaved changes?")}
              </h2>
              <p class="mt-1.5 text-sm leading-relaxed text-base-content/60">
                {gettext("You have unsaved changes. Leaving now will permanently discard them.")}
              </p>
            </div>
          </div>

          <div class="mt-6 flex justify-end gap-2.5">
            <button type="button" class="btn btn-ghost btn-sm" data-unsaved-stay>
              {gettext("Keep editing")}
            </button>
            <button type="button" class="btn btn-error btn-danger btn-sm" data-unsaved-leave>
              <span class="icon-[tabler--trash] size-3.5" />
              {gettext("Discard changes")}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the unauthenticated layout used for login, registration, and similar pages.

  ## Examples

      <Layouts.auth flash={@flash} current_scope={@current_scope}>
        <h1>Content</h1>
      </Layouts.auth>

  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")

  attr(:current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"
  )

  attr(:variant, :atom,
    default: :default,
    values: [:default, :immersive],
    doc: "the visual treatment for the unauthenticated page"
  )

  attr(:brand_placement, :atom,
    default: :outside,
    values: [:inside, :outside],
    doc: "whether the page renders its brand inside the auth card"
  )

  slot(:inner_block, required: true)

  def auth(assigns) do
    ~H"""
    <%= if @variant == :immersive do %>
      <main class="relative min-h-screen overflow-hidden bg-base-200 px-4 sm:px-6">
        <div aria-hidden="true" class="absolute inset-0 overflow-hidden">
          <div class="absolute inset-0 bg-[radial-gradient(circle_at_top_right,color-mix(in_oklch,var(--color-primary)_18%,transparent),transparent_34%),radial-gradient(circle_at_bottom_left,color-mix(in_oklch,var(--color-primary)_10%,transparent),transparent_38%)]" />
          <div class="absolute left-1/2 top-1/2 size-[34rem] -translate-x-1/2 -translate-y-1/2 rotate-[-36deg] rounded-[6rem] border border-dashed border-primary/35" />
          <div class="absolute left-1/2 top-1/2 size-[27rem] -translate-x-1/2 -translate-y-1/2 rotate-[-36deg] rounded-[5rem] border border-primary/20 bg-primary/5 shadow-[0_0_120px_color-mix(in_oklch,var(--color-primary)_12%,transparent)]" />
        </div>
        <a
          :if={@brand_placement == :outside}
          id="auth-brand"
          href={~p"/"}
          class="absolute left-1/2 top-6 z-20 -translate-x-1/2 transition-opacity hover:opacity-80 sm:top-8"
          aria-label={gettext("Konevo home page")}
        >
          <span class="flex items-center gap-2 text-xl font-semibold text-primary">
            <img src={~p"/images/logo-navbar-v2.png"} class="size-11 object-contain" alt="Konevo" />
            <span>{gettext("Konevo")}</span>
          </span>
        </a>
        <div class={[
          "relative z-10 flex min-h-screen w-full justify-center",
          if(@brand_placement == :outside,
            do: "items-center py-24",
            else: "items-start pb-12 pt-8 sm:pb-16 sm:pt-12"
          )
        ]}>
          <div class="w-full">{render_slot(@inner_block)}</div>
        </div>
      </main>
    <% else %>
      <header class="navbar px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <a href="/" class="flex-1 flex w-fit items-center gap-2">
            <img src={~p"/images/logo-navbar-v2.png"} class="size-14 object-contain" alt="Konevo" />
            <span class="text-lg font-semibold text-primary">{gettext("Konevo")}</span>
          </a>
        </div>
        <div class="flex-none">
          <ul class="flex flex-column px-1 space-x-4 items-center">
            <%= if @current_scope && @current_scope.user do %>
              <li>
                <span class="text-sm text-base-content/70">{@current_scope.user.email}</span>
              </li>
              <li>
                <.link href={~p"/users/log-out"} method="delete" class="btn btn-ghost btn-sm">
                  {gettext("Log out")}
                </.link>
              </li>
            <% else %>
              <li>
                <.link href={~p"/users/log-in"} class="btn btn-ghost btn-sm">
                  {gettext("Log in")}
                </.link>
              </li>
            <% end %>
          </ul>
        </div>
      </header>
      <main class="px-4 py-20 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-2xl space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>
    <% end %>
    <.flash_group flash={@flash} />
    """
  end

  @doc false
  def auth_brand(assigns) do
    ~H"""
    <a
      id="auth-brand"
      href={~p"/"}
      class="mx-auto flex w-full overflow-hidden transition-opacity hover:opacity-80 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-primary"
      aria-label={gettext("Konevo home page")}
    >
      <span class="mx-auto flex items-center gap-2 text-2xl font-semibold text-primary">
        <img src={~p"/images/logo-navbar-v2.png"} class="size-12 object-contain" alt="Konevo" />
        <span>{gettext("Konevo")}</span>
      </span>
    </a>
    """
  end

  @doc false
  attr(:id, :string, required: true)
  slot(:inner_block, required: true)

  def auth_card(assigns) do
    ~H"""
    <section
      id={@id}
      class="mx-auto w-full max-w-md rounded-2xl border border-secondary/35 bg-base-100/95 p-6 shadow-2xl shadow-base-content/10 backdrop-blur sm:p-8"
    >
      <div class="space-y-7 sm:space-y-8">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  @doc false
  attr(:title, :string, required: true)
  attr(:subtitle, :string, required: true)
  attr(:eyebrow, :string, default: nil)

  def auth_header(assigns) do
    ~H"""
    <div class="text-center">
      <p :if={@eyebrow} class="text-sm font-semibold text-primary">{@eyebrow}</p>
      <h1 class={[
        "text-2xl font-semibold tracking-tight text-base-content sm:text-3xl",
        @eyebrow && "mt-2"
      ]}>
        {@title}
      </h1>
      <p class="mx-auto mt-3 max-w-sm text-sm leading-6 text-base-content/65">{@subtitle}</p>
    </div>
    """
  end

  @doc """
  Renders a page content wrapper with consistent padding, an optional title,
  and an optional actions slot rendered beside the title.

  ## Examples

      <Layouts.page title="Inbox">
        <:actions>
          <.button>New message</.button>
        </:actions>
        Content here
      </Layouts.page>

  """
  attr(:title, :string, default: nil, doc: "optional page title shown in the page header")

  slot(:actions, doc: "optional action buttons rendered beside the page title")
  slot(:inner_block, required: true)

  def page(assigns) do
    ~H"""
    <div class="mx-auto max-w-screen-2xl px-4 py-4 sm:px-6 sm:py-6">
      <div :if={@title || @actions != []} class="mb-6 flex items-center justify-between gap-4">
        <h1 :if={@title} class="text-xl sm:text-2xl font-bold text-base-content">{@title}</h1>
        <div :if={@actions != []} class="flex shrink-0 items-center gap-3">
          {render_slot(@actions)}
        </div>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr(:current_scope, :map, default: nil)
  attr(:current_path, :string, default: nil)

  defp sidebar(assigns) do
    ~H"""
    <aside
      id="sidebar"
      phx-hook=".SidebarPersist"
      class="group/sidebar relative z-50 flex w-64 shrink-0 flex-col overflow-visible border-r border-base-content/20 bg-base-100"
    >
      <%!-- Header: logo always visible; text hidden when collapsed; logo centered when collapsed --%>
      <div
        data-sidebar-header
        class="flex h-16 shrink-0 items-center border-b border-base-content/20 px-3 group-[.is-collapsed]/sidebar:px-1"
      >
        <.link
          navigate={~p"/dashboard"}
          data-sidebar-brand
          class="flex flex-1 items-center gap-0.5 min-w-0 overflow-hidden group-[.is-collapsed]/sidebar:flex-none group-[.is-collapsed]/sidebar:mx-auto"
        >
          <img
            src={~p"/images/logo-navbar-v2.png"}
            class="size-10 shrink-0 object-contain"
            alt="Konevo"
          />
          <span
            data-sidebar-hide
            class="text-lg font-semibold text-primary whitespace-nowrap group-[.is-collapsed]/sidebar:hidden"
          >
            {gettext("Konevo")}
          </span>
        </.link>
      </div>

      <nav class="flex-1 overflow-y-auto px-3 py-4">
        <ul class="space-y-0.5">
          <li>
            <.link
              href={~p"/dashboard"}
              title={gettext("Dashboard")}
              aria-current={nav_active?(@current_path, "/dashboard") && "page"}
              class={[
                "sidebar-nav-link flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors hover:bg-base-200 hover:text-base-content group-[.is-collapsed]/sidebar:justify-center",
                if(nav_active?(@current_path, "/dashboard"),
                  do: "bg-base-200 text-base-content",
                  else: "text-base-content/70"
                )
              ]}
            >
              <span class="icon-[tabler--layout-dashboard] size-5 shrink-0" />
              <span data-sidebar-hide class="group-[.is-collapsed]/sidebar:hidden whitespace-nowrap">
                {gettext("Dashboard")}
              </span>
            </.link>
          </li>
          <li aria-hidden="true" class="px-3 py-1 group-[.is-collapsed]/sidebar:px-1">
            <div class="h-px bg-base-content/10"></div>
          </li>
          <li>
            <.link
              href={~p"/inbox"}
              title={gettext("Inbox")}
              aria-current={nav_active?(@current_path, "/inbox") && "page"}
              class={[
                "sidebar-nav-link flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors hover:bg-base-200 hover:text-base-content group-[.is-collapsed]/sidebar:justify-center",
                if(nav_active?(@current_path, "/inbox"),
                  do: "bg-base-200 text-base-content",
                  else: "text-base-content/70"
                )
              ]}
            >
              <span class="icon-[tabler--inbox] size-5 shrink-0" />
              <span data-sidebar-hide class="group-[.is-collapsed]/sidebar:hidden whitespace-nowrap">
                {gettext("Inbox")}
              </span>
            </.link>
          </li>
          <li>
            <.link
              href={~p"/contacts"}
              title={gettext("Contacts")}
              aria-current={nav_active?(@current_path, "/contacts") && "page"}
              class={[
                "sidebar-nav-link flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors hover:bg-base-200 hover:text-base-content group-[.is-collapsed]/sidebar:justify-center",
                if(nav_active?(@current_path, "/contacts"),
                  do: "bg-base-200 text-base-content",
                  else: "text-base-content/70"
                )
              ]}
            >
              <span class="icon-[tabler--users] size-5 shrink-0" />
              <span data-sidebar-hide class="group-[.is-collapsed]/sidebar:hidden whitespace-nowrap">
                {gettext("Contacts")}
              </span>
            </.link>
          </li>
          <li>
            <.link
              href={~p"/companies"}
              title={gettext("Companies")}
              aria-current={nav_active?(@current_path, "/companies") && "page"}
              class={[
                "sidebar-nav-link flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors hover:bg-base-200 hover:text-base-content group-[.is-collapsed]/sidebar:justify-center",
                if(nav_active?(@current_path, "/companies"),
                  do: "bg-base-200 text-base-content",
                  else: "text-base-content/70"
                )
              ]}
            >
              <span class="icon-[tabler--building] size-5 shrink-0" />
              <span data-sidebar-hide class="group-[.is-collapsed]/sidebar:hidden whitespace-nowrap">
                {gettext("Companies")}
              </span>
            </.link>
          </li>
          <li>
            <.link
              href={~p"/deals"}
              title={gettext("Deals")}
              aria-current={nav_active?(@current_path, "/deals") && "page"}
              class={[
                "sidebar-nav-link flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors hover:bg-base-200 hover:text-base-content group-[.is-collapsed]/sidebar:justify-center",
                if(nav_active?(@current_path, "/deals"),
                  do: "bg-base-200 text-base-content",
                  else: "text-base-content/70"
                )
              ]}
            >
              <span class="icon-[tabler--briefcase] size-5 shrink-0" />
              <span data-sidebar-hide class="group-[.is-collapsed]/sidebar:hidden whitespace-nowrap">
                {gettext("Deals")}
              </span>
            </.link>
          </li>
          <li>
            <.link
              href={~p"/tasks"}
              title={gettext("Tasks")}
              aria-current={nav_active?(@current_path, "/tasks") && "page"}
              class={[
                "sidebar-nav-link flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors hover:bg-base-200 hover:text-base-content group-[.is-collapsed]/sidebar:justify-center",
                if(nav_active?(@current_path, "/tasks"),
                  do: "bg-base-200 text-base-content",
                  else: "text-base-content/70"
                )
              ]}
            >
              <.icon name="icon-[tabler--checkbox]" class="size-5 shrink-0" />
              <span data-sidebar-hide class="group-[.is-collapsed]/sidebar:hidden whitespace-nowrap">
                {gettext("Tasks")}
              </span>
            </.link>
          </li>
          <li>
            <.link
              href={~p"/calendar?#{[view: "month", date: Date.to_iso8601(Date.utc_today())]}"}
              title={gettext("Calendar")}
              aria-current={nav_active?(@current_path, "/calendar") && "page"}
              class={[
                "sidebar-nav-link flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors hover:bg-base-200 hover:text-base-content group-[.is-collapsed]/sidebar:justify-center",
                if(nav_active?(@current_path, "/calendar"),
                  do: "bg-base-200 text-base-content",
                  else: "text-base-content/70"
                )
              ]}
            >
              <.icon name="icon-[tabler--calendar-week]" class="size-5 shrink-0" />
              <span data-sidebar-hide class="group-[.is-collapsed]/sidebar:hidden whitespace-nowrap">
                {gettext("Calendar")}
              </span>
            </.link>
          </li>
        </ul>
      </nav>

      <%!-- Bottom bar: account/workspace actions + sidebar collapse toggle --%>
      <div class="border-t border-base-content/20 px-3 py-3">
        <%= if @current_scope && @current_scope.user do %>
          <div
            data-sidebar-account-row
            class="flex items-center gap-2 group-[.is-collapsed]/sidebar:flex-col"
          >
            <div
              data-sidebar-user-menu
              class="relative min-w-0 flex-1 group-[.is-collapsed]/sidebar:flex-none"
              phx-click-away={
                JS.add_class("hidden", to: "#sidebar-user-menu-dropdown")
                |> JS.set_attribute({"aria-expanded", "false"}, to: "#sidebar-user-menu-button")
              }
            >
              <button
                id="sidebar-user-menu-button"
                type="button"
                phx-click={
                  JS.toggle_class("hidden", to: "#sidebar-user-menu-dropdown")
                  |> JS.toggle_attribute(
                    {"aria-expanded", "true", "false"},
                    to: "#sidebar-user-menu-button"
                  )
                }
                class={[
                  "flex w-full min-w-0 items-center gap-3 rounded-xl px-2 py-2 text-left transition-colors hover:bg-base-200",
                  "group-[.is-collapsed]/sidebar:size-10 group-[.is-collapsed]/sidebar:justify-center group-[.is-collapsed]/sidebar:p-0"
                ]}
                aria-haspopup="menu"
                aria-expanded="false"
                aria-controls="sidebar-user-menu-dropdown"
                aria-label={gettext("User menu")}
              >
                <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary text-primary-content ring-2 ring-primary/15">
                  <span class="text-xs font-semibold">
                    {user_initials(@current_scope.user)}
                  </span>
                </div>
                <div data-sidebar-hide class="min-w-0 flex-1 group-[.is-collapsed]/sidebar:hidden">
                  <p class="truncate text-[14px] font-semibold leading-4 text-base-content">
                    {user_display_name(@current_scope.user)}
                  </p>
                  <p class="truncate text-[14px] leading-4 text-base-content/55">
                    {@current_scope.user.email}
                  </p>
                </div>
              </button>
              <ul
                id="sidebar-user-menu-dropdown"
                class={[
                  "hidden absolute bottom-full left-0 z-60 mb-2 w-56 overflow-hidden rounded-xl border border-base-content/15 bg-base-100 p-1 shadow-xl shadow-base-content/10",
                  "group-[.is-collapsed]/sidebar:-left-3"
                ]}
                role="menu"
              >
                <li>
                  <.link href={~p"/automation"} class="dropdown-item text-[14px]">
                    <.icon name="icon-[tabler--bolt]" class="size-4" />
                    {gettext("Automation")}
                  </.link>
                </li>
                <li>
                  <.link href={~p"/settings"} class="dropdown-item text-[14px]">
                    <.icon name="icon-[tabler--settings]" class="size-4" />
                    {gettext("Settings")}
                  </.link>
                </li>
                <li>
                  <.link href={~p"/team"} class="dropdown-item text-[14px]">
                    <.icon name="icon-[tabler--users-group]" class="size-4" />
                    {gettext("Team")}
                  </.link>
                </li>
                <li :if={main_tenant_owner?(@current_scope)}>
                  <.link href={~p"/tenants"} class="dropdown-item text-[14px]">
                    <.icon name="icon-[tabler--buildings]" class="size-4" />
                    {gettext("Tenants")}
                  </.link>
                </li>
                <%!-- Temporarily hidden until support requests are re-enabled.
                <li>
                  <.link
                    href={~p"/support"}
                    id="sidebar-support-link"
                    class="dropdown-item text-[14px]"
                  >
                    <.icon name="icon-[tabler--lifebuoy]" class="size-4" />
                    {gettext("Support")}
                  </.link>
                </li>
                --%>
                <li class="border-t border-base-content/10">
                  <.link
                    href={~p"/users/log-out"}
                    method="delete"
                    class="dropdown-item danger-action text-[14px]"
                  >
                    <.icon name="icon-[tabler--logout]" class="size-4" />
                    {gettext("Log out")}
                  </.link>
                </li>
              </ul>
            </div>

            <div class="flex shrink-0 items-center justify-center">
              <%!-- Mobile collapse toggle --%>
              <button
                id="sidebar-mobile-collapse-button"
                type="button"
                phx-click={JS.toggle_class("is-collapsed", to: "#sidebar")}
                class="btn btn-ghost btn-sm btn-square shrink-0 lg:hidden"
                aria-label={gettext("Toggle sidebar")}
              >
                <.icon
                  name="icon-[tabler--chevrons-left]"
                  data-sidebar-hide
                  class="size-5 group-[.is-collapsed]/sidebar:hidden"
                />
                <.icon
                  name="icon-[tabler--chevrons-right]"
                  data-sidebar-show
                  class="size-5 hidden group-[.is-collapsed]/sidebar:flex"
                />
              </button>
              <%!-- Desktop collapse toggle --%>
              <button
                id="sidebar-desktop-collapse-button"
                type="button"
                phx-click={JS.toggle_class("is-collapsed", to: "#sidebar")}
                class="btn btn-ghost btn-sm btn-square shrink-0 hidden lg:flex"
                aria-label={gettext("Toggle sidebar")}
              >
                <.icon
                  name="icon-[tabler--chevrons-left]"
                  data-sidebar-hide
                  class="size-5 group-[.is-collapsed]/sidebar:hidden"
                />
                <.icon
                  name="icon-[tabler--chevrons-right]"
                  data-sidebar-show
                  class="size-5 hidden group-[.is-collapsed]/sidebar:flex"
                />
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </aside>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SidebarPersist">
      export default {
        mounted() {
          if (localStorage.getItem("sidebar:collapsed") === "1") {
            this.el.classList.add("is-collapsed");
          }
          // Hand off from the pre-JS CSS rule to the JS-driven class
          document.documentElement.removeAttribute("data-sidebar-collapsed");
          this._observer = new MutationObserver(() => {
            if (!window.matchMedia("(min-width: 1024px)").matches) return;

            if (this.el.classList.contains("is-collapsed")) {
              localStorage.setItem("sidebar:collapsed", "1");
            } else {
              localStorage.removeItem("sidebar:collapsed");
            }
          });
          this._observer.observe(this.el, { attributes: true, attributeFilter: ["class"] });
        },
        beforeUpdate() {
          this._collapsedBeforeUpdate = this.el.classList.contains("is-collapsed");
        },
        updated() {
          this.el.classList.toggle("is-collapsed", this._collapsedBeforeUpdate);
        },
        destroyed() {
          this._observer?.disconnect();
        },
      }
    </script>
    """
  end

  defp nav_active?(nil, _path), do: false
  defp nav_active?(_current, "#"), do: false
  defp nav_active?(current, "/"), do: current == "/"

  defp nav_active?(current, path),
    do: current == path or String.starts_with?(current, path <> "/")

  defp user_initials(%{email: email}) when is_binary(email) do
    email
    |> String.upcase()
    |> String.slice(0, 2)
  end

  defp user_initials(_user), do: "U"

  defp user_display_name(user) do
    case Map.get(user, :name) do
      name when is_binary(name) and name != "" ->
        name

      _ ->
        user
        |> Map.get(:email, "")
        |> String.split("@")
        |> List.first()
        |> String.replace(~r/[._-]+/, " ")
        |> String.split()
        |> Enum.map_join(" ", &String.capitalize/1)
    end
  end

  defp main_tenant_owner?(%{org: %{slug: slug}, membership: %{role: :owner}}) do
    slug == Application.fetch_env!(:konevo, :default_tenant_slug)
  end

  defp main_tenant_owner?(_scope), do: false

  attr(:current_scope, :map, required: true)

  defp topbar(assigns) do
    ~H"""
    <header class="relative flex h-16 shrink-0 items-center justify-between border-b border-base-content/20 bg-base-100 px-4 lg:px-6">
      <div class="flex items-center gap-2">
        <%!-- Mobile menu toggle: hamburger becomes a close control while open --%>
        <button
          id="mobile-menu-toggle"
          type="button"
          phx-click={
            JS.toggle_class("is-open", to: "#sidebar")
            |> JS.add_class("is-collapsed", to: "#sidebar")
            |> JS.toggle_class("hidden", to: "#sidebar-backdrop")
            |> JS.toggle_class("hidden", to: "#mobile-menu-open-icon")
            |> JS.toggle_class("hidden", to: "#mobile-menu-close-icon")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#mobile-menu-toggle")
            |> JS.toggle_attribute({"aria-label", gettext("Close menu"), gettext("Open menu")},
              to: "#mobile-menu-toggle"
            )
          }
          class="topbar-action btn btn-ghost btn-sm btn-square lg:hidden"
          aria-label={gettext("Open menu")}
          aria-controls="sidebar"
          aria-expanded="false"
        >
          <.icon id="mobile-menu-open-icon" name="icon-[tabler--menu-2]" class="size-5" />
          <.icon id="mobile-menu-close-icon" name="icon-[tabler--x]" class="hidden size-5" />
        </button>
      </div>

      <div class="absolute left-1/2 z-30 w-[min(15rem,calc(100%-9rem))] -translate-x-1/2 sm:w-[min(34rem,calc(100%-8rem))] xl:w-[36rem]">
        <.live_component
          module={KonevoWeb.GlobalSearchComponent}
          id="global-search"
          current_scope={@current_scope}
        />
      </div>
    </header>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")
  attr(:id, :string, default: "flash-group", doc: "the optional id of flash container")

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:success} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <span class="icon-[tabler--refresh] ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <span class="icon-[tabler--refresh] ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  attr(:class, :string, default: nil)

  def theme_toggle(assigns) do
    ~H"""
    <div class="dropdown relative inline-flex">
      <button
        id="topbar-theme-button"
        type="button"
        class={["topbar-action btn btn-ghost btn-sm gap-1", @class]}
        aria-haspopup="menu"
        aria-expanded="false"
        aria-label="Theme"
      >
        <.icon name="icon-[tabler--palette]" class="size-4" />
        <span class="hidden sm:inline text-xs">Theme</span>
        <.icon name="icon-[tabler--chevron-down]" class="size-3 opacity-60" />
      </button>
      <ul
        class="dropdown-menu dropdown-open:opacity-100 hidden min-w-36"
        role="menu"
        aria-orientation="vertical"
      >
        <%= for {label, theme} <- [
          {"Light", "corporate"},
          {"Dark", "vscode"}
        ] do %>
          <li>
            <button
              type="button"
              class="dropdown-item"
              phx-click={JS.dispatch("phx:set-theme")}
              data-phx-theme={theme}
            >
              {label}
            </button>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end
end
