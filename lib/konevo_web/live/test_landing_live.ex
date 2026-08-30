defmodule KonevoWeb.TestLandingLive do
  use KonevoWeb, :live_view

  alias Konevo.Security.RateLimiter
  alias KonevoWeb.ClientIp

  @preview_pages ~w(dashboard inbox contacts companies deals calendar tasks)
  @preview_autoplay_interval 9_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, gettext("Self-hosted AI Inbox | Konevo"))
      |> assign(
        :seo_description,
        gettext(
          "Turn inbox conversations into contacts, tasks, and reviewable follow-ups with a self-hosted AI CRM."
        )
      )
      |> assign(:seo_json_ld, Seo.software_application_json_ld())
      |> assign(:seo_robots, "index, follow")
      |> assign(:seo_url, Seo.page_url("/"))
      |> assign(:preview_pages, @preview_pages)
      |> assign(:active_preview, "dashboard")
      |> assign(:preview_timer_ref, nil)
      |> assign(:preview_timer_token, nil)

    if connected?(socket) do
      case RateLimiter.check(:public_landing, ip: ClientIp.from_socket(socket)) do
        :ok -> {:ok, schedule_preview_advance(socket)}
        {:error, _retry_after} -> {:ok, redirect(socket, to: ~p"/terms")}
      end
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("select_preview", %{"page" => page}, socket) when page in @preview_pages do
    {:noreply, socket |> assign(:active_preview, page) |> schedule_preview_advance()}
  end

  def handle_event("select_preview", _params, socket), do: {:noreply, socket}

  def handle_event("previous_preview", _params, socket) do
    {:noreply,
     socket
     |> assign(:active_preview, cycle_preview(socket.assigns.active_preview, -1))
     |> schedule_preview_advance()}
  end

  def handle_event("next_preview", _params, socket) do
    {:noreply,
     socket
     |> assign(:active_preview, cycle_preview(socket.assigns.active_preview, 1))
     |> schedule_preview_advance()}
  end

  def handle_event("pause_preview", _params, socket),
    do: {:noreply, cancel_preview_advance(socket)}

  def handle_event("resume_preview", _params, socket),
    do: {:noreply, schedule_preview_advance(socket)}

  @impl true
  def handle_info({:advance_preview, token}, socket) do
    if socket.assigns.preview_timer_token == token do
      {:noreply,
       socket
       |> assign(:active_preview, cycle_preview(socket.assigns.active_preview, 1))
       |> schedule_preview_advance()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="test-landing" class="min-h-screen overflow-hidden bg-base-100 text-base-content">
      <section class="relative isolate overflow-hidden">
        <div aria-hidden="true" class="landing-grid absolute inset-0 -z-10 opacity-55" />
        <div
          aria-hidden="true"
          class="landing-glow absolute -right-48 -top-52 -z-10 size-[42rem] rounded-full"
        />

        <header class="mx-auto flex max-w-7xl items-center justify-between px-5 py-3 sm:px-8 sm:py-5 lg:px-10">
          <a
            id="test-landing-brand"
            href={~p"/"}
            class="flex items-center gap-2.5"
            aria-label={gettext("Konevo home page")}
          >
            <span class="flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-xl sm:size-12">
              <img
                src={~p"/images/logo-navbar-v2.png"}
                alt=""
                class="size-10 object-contain sm:size-12"
              />
            </span>
            <span class="text-base font-bold tracking-tight text-primary sm:text-lg">Konevo</span>
          </a>

          <nav
            id="test-landing-navigation"
            phx-hook=".LandingNavigation"
            phx-update="ignore"
            class="hidden items-center gap-6 text-sm font-semibold text-base-content/65 md:flex"
            aria-label={gettext("Marketing navigation")}
          >
            <button
              id="test-landing-nav-product"
              type="button"
              data-nav-static
              data-nav-item
              data-nav-section="#product"
              aria-current="page"
              class="px-1 py-2 text-primary underline decoration-2 underline-offset-[0.32em] transition-colors duration-200 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              {gettext("Product")}
            </button>
            <a
              id="test-landing-nav-how-it-works"
              href="#how-it-works"
              data-nav-item
              class="px-1 py-2 transition-colors duration-200 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              {gettext("How it works")}
            </a>
            <a
              id="test-landing-nav-installation"
              href="#installation"
              data-nav-item
              class="px-1 py-2 transition-colors duration-200 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              {gettext("Installation")}
            </a>
            <a
              id="test-landing-nav-contact"
              href="#contact"
              data-nav-item
              class="px-1 py-2 transition-colors duration-200 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              {gettext("Contact")}
            </a>
          </nav>

          <div class="flex items-center gap-2 sm:gap-3">
            <button
              id="test-landing-theme-toggle"
              type="button"
              phx-hook=".LandingThemeToggle"
              phx-update="ignore"
              class="btn btn-neutral btn-sm btn-square"
              data-light-label={gettext("Use light theme")}
              data-dark-label={gettext("Use dark theme")}
              aria-label={gettext("Use dark theme")}
            >
              <.icon data-theme-icon="sun" name="icon-[tabler--sun]" class="hidden size-4" />
              <.icon data-theme-icon="moon" name="icon-[tabler--moon]" class="size-4" />
            </button>
            <.link
              id="test-landing-view-examples"
              navigate={~p"/demo"}
              class="btn btn-primary btn-sm w-9 min-w-9 px-0 font-semibold shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:shadow-primary/30 sm:w-auto sm:min-w-0 sm:gap-2 sm:px-4"
            >
              <.icon name="icon-[tabler--sparkles]" class="size-4" />
              <span class="hidden sm:inline">{gettext("View examples")}</span>
              <span class="sr-only sm:hidden">{gettext("View examples")}</span>
            </.link>
          </div>
        </header>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".LandingThemeToggle">
          export default {
            mounted() {
              this.sun = this.el.querySelector('[data-theme-icon="sun"]')
              this.moon = this.el.querySelector('[data-theme-icon="moon"]')
              this.onClick = () => {
                const nextTheme = document.documentElement.dataset.theme === "vscode"
                  ? "corporate"
                  : "vscode"

                localStorage.setItem("phx:theme", nextTheme)
                document.documentElement.setAttribute("data-theme", nextTheme)
                this.render(nextTheme)
              }

              this.el.addEventListener("click", this.onClick)
              this.render(document.documentElement.dataset.theme || "corporate")
            },
            render(theme) {
              const dark = theme === "vscode"
              this.sun.classList.toggle("hidden", !dark)
              this.moon.classList.toggle("hidden", dark)
              this.el.setAttribute("aria-label", dark ? this.el.dataset.lightLabel : this.el.dataset.darkLabel)
            },
            destroyed() {
              this.el.removeEventListener("click", this.onClick)
            }
          }
        </script>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".LandingNavigation">
          export default {
            mounted() {
              const navItems = [...this.el.querySelectorAll("[data-nav-item]")]
              const links = navItems.filter(item => item.matches('a[href^="#"]'))
              const sections = navItems
                .map(item => ({
                  item,
                  section: document.querySelector(item.dataset.navSection || item.getAttribute("href"))
                }))
                .filter(({section}) => section)

              const replaceHash = item => {
                const hash = item.getAttribute("href") || ""

                if (window.location.hash !== hash) {
                  history.replaceState(null, "", hash || `${window.location.pathname}${window.location.search}`)
                }
              }

              const setActive = activeLink => {
                navItems.forEach(item => {
                  const active = item === activeLink
                  item.classList.toggle("text-primary", active)
                  item.classList.toggle("text-base-content/65", !active)
                  item.style.textDecoration = active ? "underline" : "none"
                  item.style.textUnderlineOffset = "0.32em"
                  item.style.textDecorationThickness = "2px"
                  item.toggleAttribute("aria-current", active)
                })
              }

              const updateActiveSection = () => {
                const marker = window.scrollY + window.innerHeight * 0.35
                const atPageBottom =
                  Math.ceil(window.scrollY + window.innerHeight) >= document.documentElement.scrollHeight
                const active = atPageBottom
                  ? sections[sections.length - 1]
                  : sections.reduce((current, candidate) =>
                    candidate.section.offsetTop <= marker ? candidate : current
                  )

                if (active) {
                  setActive(active.item)
                  replaceHash(active.item)
                }
              }

              this.onNavigationClick = event => {
                const link = event.target.closest("[data-nav-item]")

                if (!link || !this.el.contains(link)) return

                if (link.hasAttribute("data-nav-static")) {
                  event.preventDefault()
                  setActive(link)
                  replaceHash(link)
                  return
                }

                const section = document.querySelector(link.getAttribute("href"))
                if (!section) return

                event.preventDefault()
                setActive(link)
                history.pushState(null, "", link.hash)
                section.scrollIntoView({
                  behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
                    ? "auto"
                    : "smooth",
                  block: "start"
                })
              }

              this.onScroll = () => requestAnimationFrame(updateActiveSection)
              this.el.addEventListener("click", this.onNavigationClick)
              window.addEventListener("scroll", this.onScroll, {passive: true})
              const initialItem =
                links.find(link => link.hash === window.location.hash) ||
                  navItems.find(item => item.hasAttribute("data-nav-static"))

              setActive(initialItem)
              updateActiveSection()
            },
            destroyed() {
              this.el.removeEventListener("click", this.onNavigationClick)
              window.removeEventListener("scroll", this.onScroll)
            }
          }
        </script>

        <% preview = preview_copy(@active_preview) %>
        <div class="mx-auto grid max-w-7xl gap-8 px-5 pb-12 pt-8 sm:gap-12 sm:px-8 sm:pb-16 sm:pt-10 lg:grid-cols-[.78fr_1.22fr] lg:items-start lg:px-10 lg:pb-24">
          <div class="min-w-0 max-w-2xl">
            <div class="inline-flex items-center gap-2 rounded-full border border-primary/20 bg-primary/10 px-3 py-1.5 text-xs font-semibold text-primary">
              <span class="flex size-4 items-center justify-center rounded-full bg-primary text-primary-content">
                <.icon name={preview.icon} class="size-3" />
              </span>
              {preview.label}
            </div>
            <h1 class="mt-4 text-3xl font-bold leading-[0.98] tracking-[-0.055em] text-balance sm:mt-6 sm:text-6xl lg:text-7xl">
              {preview.title}
            </h1>
            <p class="mt-4 max-h-12 max-w-xl overflow-hidden text-sm leading-6 text-base-content/65 sm:mt-6 sm:max-h-none sm:text-lg sm:leading-8">
              {preview.description}
            </p>
            <p class="hidden mt-6 max-w-xl text-lg leading-8 text-base-content/65">
              {gettext(
                "Konevo turns customer conversations into contacts, tasks, and follow-ups—so your team can protect every lead without the CRM busywork."
              )}
            </p>
            <div class="hidden mt-7 flex-col gap-3 sm:mt-8 sm:flex sm:flex-row">
              <a
                id="test-landing-hero-source-available"
                href="https://github.com/FilipPauco/konevo"
                target="_blank"
                rel="noreferrer"
                class="btn btn-primary btn-md w-full gap-2 px-4 shadow-none transition-transform duration-150 hover:shadow-none active:shadow-none sm:btn-lg sm:w-auto sm:px-6 sm:hover:-translate-y-0.5 motion-reduce:transform-none"
              >
                <.icon name="icon-[tabler--brand-github]" class="size-5" />
                {gettext("View source")}
              </a>
              <a
                id="test-landing-hero-how-it-works"
                href="#how-it-works"
                class="hidden btn btn-ghost btn-md w-full gap-2 px-4 shadow-none transition-transform duration-150 hover:shadow-none active:shadow-none sm:flex sm:btn-lg sm:w-auto sm:px-6 sm:hover:-translate-y-0.5 motion-reduce:transform-none"
              >
                <.icon name="icon-[tabler--player-play]" class="size-4" />
                {gettext("See how it works")}
              </a>
            </div>
            <div class="mt-8 hidden flex-wrap gap-x-5 gap-y-3 text-sm text-base-content/60 sm:flex">
              <.assurance
                icon="icon-[tabler--circle-check]"
                label={gettext("Free for personal and internal use")}
              />
              <.assurance
                icon="icon-[tabler--circle-check]"
                label={gettext("Your data stays with you")}
              />
              <.assurance
                icon="icon-[tabler--shield-lock]"
                label={gettext("Enhanced security with MFA")}
              />
            </div>
          </div>

          <div
            id="product"
            phx-hook=".PreviewAutoplay"
            class="relative mx-auto min-w-0 w-full max-w-3xl lg:mx-0"
          >
            <div
              aria-hidden="true"
              class="absolute -inset-4 -z-10 rounded-[2rem] bg-primary/10 blur-2xl sm:-inset-6 sm:blur-3xl"
            />
            <.product_preview active_page={@active_preview} />
            <div
              :if={false}
              class="hidden overflow-hidden rounded-2xl border border-base-content/12 bg-base-100 shadow-2xl shadow-base-content/15"
            >
              <div class="flex items-center gap-2 border-b border-base-content/10 bg-base-200/50 px-4 py-3">
                <span class="flex size-6 items-center justify-center rounded-md bg-primary/10 text-primary">
                  <.icon name="icon-[tabler--browser]" class="size-3.5" />
                </span>
                <div class="ml-1 flex h-6 flex-1 items-center rounded-md bg-base-100 px-2.5 text-[10px] text-base-content/40">
                  konevo/dashboard
                </div>
              </div>
              <div class="grid min-h-[29rem] grid-cols-[3.3rem_minmax(0,1fr)] sm:grid-cols-[9.5rem_minmax(0,1fr)]">
                <aside class="border-r border-base-content/10 bg-base-200/35 p-2 sm:p-3">
                  <div class="mb-6 hidden items-center gap-2 px-2 sm:flex">
                    <span class="flex size-6 items-center justify-center rounded-md bg-primary text-primary-content">
                      <.icon name="icon-[tabler--bolt]" class="size-3.5" />
                    </span>
                    <span class="text-xs font-bold">Konevo</span>
                  </div>
                  <nav class="space-y-1" aria-label={gettext("Product preview navigation")}>
                    <.preview_nav
                      page="home"
                      icon="icon-[tabler--layout-dashboard]"
                      label={gettext("Home")}
                      active_page="home"
                    />
                    <.preview_nav
                      page="inbox"
                      icon="icon-[tabler--inbox]"
                      label={gettext("Inbox")}
                      badge="8"
                      active_page="home"
                    />
                    <.preview_nav
                      page="contacts"
                      icon="icon-[tabler--users]"
                      label={gettext("Contacts")}
                      active_page="home"
                    />
                    <.preview_nav
                      page="deals"
                      icon="icon-[tabler--briefcase]"
                      label={gettext("Deals")}
                      active_page="home"
                    />
                    <.preview_nav
                      page="tasks"
                      icon="icon-[tabler--checkbox]"
                      label={gettext("Tasks")}
                      active_page="home"
                    />
                  </nav>
                </aside>
                <div class="min-w-0 p-3 sm:p-5">
                  <div class="flex items-start justify-between gap-3">
                    <div>
                      <p class="text-[10px] font-semibold uppercase tracking-[0.16em] text-primary">
                        {gettext("Tuesday brief")}
                      </p>
                      <h2 class="mt-1 text-base font-bold sm:text-lg">
                        {gettext("Everything that needs you")}
                      </h2>
                    </div>
                    <span class="flex size-8 items-center justify-center rounded-lg border border-base-content/10 bg-base-100 text-primary">
                      <.icon name="icon-[tabler--sparkles]" class="size-4" />
                    </span>
                  </div>

                  <div class="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
                    <.preview_metric label={gettext("Needs reply")} value="8" tone="warning" />
                    <.preview_metric label={gettext("At risk")} value="€12.4k" tone="error" />
                    <.preview_metric label={gettext("Tasks due")} value="5" tone="primary" />
                    <.preview_metric label={gettext("Closing soon")} value="3" tone="success" />
                  </div>

                  <div class="mt-4 grid gap-3 lg:grid-cols-[1.1fr_.9fr]">
                    <section class="rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm">
                      <div class="flex items-center justify-between">
                        <div>
                          <h3 class="text-xs font-bold">{gettext("Priority queue")}</h3>
                          <p class="mt-0.5 text-[10px] text-base-content/50">
                            {gettext("Leads waiting on your reply")}
                          </p>
                        </div>
                        <.icon name="icon-[tabler--mail-exclamation]" class="size-4 text-warning" />
                      </div>
                      <div class="mt-2 divide-y divide-base-content/8">
                        <.preview_row
                          initials="AC"
                          name="Acme Studio"
                          detail={gettext("Proposal follow-up")}
                          age="2h"
                        />
                        <.preview_row
                          initials="RL"
                          name="Riviera Labs"
                          detail={gettext("Pricing question")}
                          age="4h"
                        />
                        <.preview_row
                          initials="PN"
                          name="Pine & North"
                          detail={gettext("New enquiry")}
                          age="5h"
                        />
                      </div>
                    </section>
                    <section class="rounded-xl border border-primary/18 bg-primary/6 p-3">
                      <div class="flex items-center justify-between">
                        <h3 class="text-xs font-bold">{gettext("AI next step")}</h3>
                        <.icon name="icon-[tabler--sparkles]" class="size-4 text-primary" />
                      </div>
                      <p class="mt-3 text-xs font-medium leading-5">
                        {gettext(
                          "Draft a warm follow-up for Acme Studio. Their proposal has been quiet for 5 days."
                        )}
                      </p>
                      <button
                        id="test-landing-preview-draft"
                        type="button"
                        class="btn btn-primary btn-xs mt-3 w-full gap-1.5"
                      >
                        <.icon name="icon-[tabler--pencil]" class="size-3" />
                        {gettext("Review draft")}
                      </button>
                    </section>
                  </div>

                  <section class="mt-3 rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm">
                    <div class="flex items-center justify-between">
                      <div>
                        <h3 class="text-xs font-bold">{gettext("Pipeline")}</h3>
                        <p class="mt-0.5 text-[10px] text-base-content/50">
                          {gettext("€36.8k active opportunities")}
                        </p>
                      </div>
                      <.icon name="icon-[tabler--chart-arrows]" class="size-4 text-primary" />
                    </div>
                    <div class="mt-3 grid grid-cols-4 gap-2">
                      <.pipeline_column label={gettext("New")} value="€9k" count="3" />
                      <.pipeline_column label={gettext("Qualified")} value="€11k" count="4" />
                      <.pipeline_column label={gettext("Proposal")} value="€12k" count="2" />
                      <.pipeline_column label={gettext("Close")} value="€5k" count="1" />
                    </div>
                  </section>
                </div>
              </div>
            </div>
            <div
              class="mt-5 flex items-center justify-center gap-4"
              aria-label={gettext("Product preview carousel controls")}
            >
              <button
                id="test-landing-previous-preview"
                type="button"
                phx-click="previous_preview"
                class="btn btn-circle btn-md btn-outline border-base-content/15 text-base-content transition-transform duration-150 hover:border-primary hover:bg-primary hover:text-primary-content active:scale-90 phx-click-loading:scale-90 phx-click-loading:opacity-70 sm:btn-sm"
                aria-label={gettext("Show previous product screen")}
              >
                <.icon name="icon-[tabler--arrow-left]" class="size-4" />
              </button>
              <div
                class="flex items-center gap-2"
                role="tablist"
                aria-label={gettext("Product screens")}
              >
                <button
                  :for={page <- @preview_pages}
                  id={"test-landing-preview-dot-#{page}"}
                  type="button"
                  role="tab"
                  phx-click="select_preview"
                  phx-value-page={page}
                  aria-label={gettext("Show product screen") <> ": " <> preview_copy(page).label}
                  aria-selected={@active_preview == page}
                  class={[
                    "rounded-full transition-all duration-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                    @active_preview == page && "h-2.5 w-6 bg-primary",
                    @active_preview != page && "size-2 bg-base-content/20 hover:bg-base-content/45"
                  ]}
                />
              </div>
              <button
                id="test-landing-next-preview"
                type="button"
                phx-click="next_preview"
                class="btn btn-circle btn-md btn-primary shadow-none transition-transform duration-150 active:scale-90 phx-click-loading:scale-90 phx-click-loading:opacity-80 sm:btn-sm sm:shadow-lg sm:shadow-primary/20"
                aria-label={gettext("Show next product screen")}
              >
                <.icon name="icon-[tabler--arrow-right]" class="size-4" />
              </button>
            </div>
            <a
              href="https://github.com/FilipPauco/konevo"
              target="_blank"
              rel="noreferrer"
              class="btn btn-primary btn-md mt-8 w-full gap-2 shadow-none transition-transform duration-150 hover:-translate-y-0.5 hover:shadow-none active:shadow-none motion-reduce:transform-none sm:hidden"
            >
              <.icon name="icon-[tabler--brand-github]" class="size-5" />
              {gettext("View source")}
            </a>
          </div>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".PreviewAutoplay">
            export default {
              mounted() {
                this.pauseTimer = null
                this.pause = () => {
                  clearTimeout(this.pauseTimer)
                  this.pauseTimer = setTimeout(() => this.pushEvent("pause_preview", {}), 250)
                }
                this.resume = () => {
                  clearTimeout(this.pauseTimer)
                  this.pushEvent("resume_preview", {})
                }
                this.cancelPendingPause = () => clearTimeout(this.pauseTimer)
                this.el.addEventListener("mouseenter", this.pause)
                this.el.addEventListener("mouseleave", this.resume)
                this.el.addEventListener("focusin", this.pause)
                this.el.addEventListener("focusout", this.resume)
                this.el.addEventListener("click", this.cancelPendingPause, true)
              },
              destroyed() {
                clearTimeout(this.pauseTimer)
                this.el.removeEventListener("mouseenter", this.pause)
                this.el.removeEventListener("mouseleave", this.resume)
                this.el.removeEventListener("focusin", this.pause)
                this.el.removeEventListener("focusout", this.resume)
                this.el.removeEventListener("click", this.cancelPendingPause, true)
              }
            }
          </script>
        </div>
      </section>

      <section id="principles" class="landing-section-tint border-t border-base-content/15">
        <div class="mx-auto max-w-7xl px-5 py-20 sm:px-8 lg:px-10 lg:py-28">
          <div class="mx-auto max-w-2xl text-center">
            <p class="text-sm font-semibold text-primary">{gettext("Open by design")}</p>
            <h2 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
              {gettext("Built to earn your trust.")}
            </h2>
            <p class="mt-4 text-base leading-7 text-base-content/60">
              {gettext("Clear principles, practical terms, and control that stays with your team.")}
            </p>
          </div>
          <div class="mx-auto mt-12 grid max-w-6xl gap-4 md:grid-cols-3">
            <.technology_card
              id="test-landing-source-available"
              icon="icon-[tabler--brand-github]"
              title={gettext("Transparent")}
              description={
                gettext(
                  "The source code is publicly available to inspect and understand how Konevo works."
                )
              }
              badge={gettext("Public source")}
            />
            <.technology_card
              id="test-landing-free-to-use"
              icon="icon-[tabler--heart-handshake]"
              title={gettext("Free to use")}
              description={
                gettext("Use Konevo at no cost, subject to the terms in the project license.")
              }
              badge={gettext("Under the license")}
            />
            <.technology_card
              id="test-landing-data-ownership"
              icon="icon-[tabler--lock]"
              title={gettext("Private and secure")}
              description={
                gettext(
                  "Your customer information stays in your control. Two-factor authentication adds protection to every sign-in."
                )
              }
              badge={gettext("Your control")}
            />
          </div>
        </div>
      </section>

      <section id="how-it-works" class="border-t border-base-content/15">
        <div class="mx-auto max-w-7xl px-5 py-20 sm:px-8 lg:px-10 lg:py-28">
          <div class="max-w-2xl">
            <h2 class="text-3xl font-bold tracking-tight sm:text-4xl">
              {gettext("From inbox to follow-up, without the busywork.")}
            </h2>
            <p class="mt-4 text-base leading-7 text-base-content/60">
              {gettext(
                "Konevo makes your inbox the source of truth, then gives every conversation a clear next move."
              )}
            </p>
          </div>
          <div class="mt-12 grid gap-4 md:grid-cols-3">
            <.feature_card
              number="01"
              icon="icon-[tabler--mail-ai]"
              title={gettext("Connect your inbox")}
              description={
                gettext(
                  "Bring conversations, customers, and context together without manual importing."
                )
              }
            />
            <.feature_card
              number="02"
              icon="icon-[tabler--sparkles]"
              title={gettext("Let AI find the signal")}
              description={
                gettext(
                  "Spot waiting leads, extract tasks, and prepare thoughtful replies with context."
                )
              }
            />
            <.feature_card
              number="03"
              icon="icon-[tabler--arrow-up-right]"
              title={gettext("Keep every opportunity moving")}
              description={
                gettext("Follow through with a focused queue, shared pipeline, and timely reminders.")
              }
            />
          </div>
          <div class="mt-16 grid gap-10 border-t border-base-content/8 pt-16 lg:grid-cols-[0.78fr_1.22fr] lg:items-center">
            <div class="max-w-xl">
              <p class="text-sm font-semibold text-primary">{gettext("Set the right context")}</p>
              <h3 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
                {gettext("AI that understands how your team works.")}
              </h3>
              <p class="mt-4 text-base leading-7 text-base-content/60">
                {gettext(
                  "Tell Konevo about your business, your preferred tone, and the rules that matter. Every AI draft starts with that shared context."
                )}
              </p>
              <div class="mt-7 flex items-center gap-2 text-sm font-medium text-primary">
                <.icon name="icon-[tabler--sparkles]" class="size-4" />
                {gettext("Your context stays in your workspace")}
              </div>
            </div>
            <div class="landing-product-demo overflow-hidden rounded-2xl border border-base-content/12 bg-base-100 shadow-2xl shadow-base-content/12">
              <div class="flex items-center gap-2 border-b border-base-content/10 bg-base-200/55 px-4 py-3">
                <span class="flex size-6 items-center justify-center rounded-md bg-primary/10 text-primary">
                  <.icon name="icon-[tabler--browser]" class="size-3.5" />
                </span>
                <div class="ml-1 flex h-6 flex-1 items-center rounded-md bg-base-100 px-2.5 text-[10px] text-base-content/40">
                  konevo/settings/ai
                </div>
              </div>
              <div class="h-[24rem] p-3 sm:h-[31rem] sm:p-5">
                <.ai_settings_preview />
              </div>
            </div>
          </div>
        </div>
      </section>

      <section id="ai-drafting" class="landing-section-tint border-t border-base-content/15">
        <div class="mx-auto grid max-w-7xl gap-10 px-5 py-20 sm:px-8 lg:grid-cols-[0.78fr_1.22fr] lg:items-center lg:px-10 lg:py-28">
          <div class="max-w-xl">
            <p class="text-sm font-semibold text-primary">{gettext("A thoughtful first draft")}</p>
            <h2 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
              {gettext("Turn a waiting email into a reply in a moment.")}
            </h2>
            <p class="mt-4 text-base leading-7 text-base-content/60">
              {gettext(
                "Konevo brings the conversation into view, prepares a clear reply, and leaves your team in control of the final send."
              )}
            </p>
            <div class="mt-7 space-y-4 text-sm leading-6 text-base-content/65">
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--sparkles]" class="size-4" />
                </span>
                <p>{gettext("A draft starts with the context already in the thread.")}</p>
              </div>
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--edit]" class="size-4" />
                </span>
                <p>{gettext("Review, adjust the tone, then send when it feels right.")}</p>
              </div>
            </div>
          </div>
          <.ai_draft_demo />
        </div>
      </section>

      <section id="contact-extraction" class="border-t border-base-content/15">
        <div class="mx-auto grid max-w-7xl gap-10 px-5 py-20 sm:px-8 lg:grid-cols-[1.22fr_0.78fr] lg:items-center lg:px-10 lg:py-28">
          <div class="order-2 lg:order-none"><.contact_extract_demo /></div>
          <div class="order-1 max-w-xl lg:order-none lg:justify-self-end">
            <p class="text-sm font-semibold text-primary">{gettext("Keep your CRM current")}</p>
            <h2 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
              {gettext("Create contacts and companies from the conversation.")}
            </h2>
            <p class="mt-4 text-base leading-7 text-base-content/60">
              {gettext(
                "When a new person emails you, Konevo can open a ready-to-review record with the useful details already in place."
              )}
            </p>
            <div class="mt-7 space-y-4 text-sm leading-6 text-base-content/65">
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--user-plus]" class="size-4" />
                </span>
                <p>{gettext("Capture a contact without retyping their name or email.")}</p>
              </div>
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--building-plus]" class="size-4" />
                </span>
                <p>{gettext("Create the company record from the same email context.")}</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section id="workflow-automation" class="landing-section-tint border-t border-base-content/15">
        <div class="mx-auto grid max-w-7xl gap-10 px-5 py-20 sm:px-8 lg:grid-cols-[0.78fr_1.22fr] lg:items-center lg:px-10 lg:py-28">
          <div class="max-w-xl">
            <p class="text-sm font-semibold text-primary">
              {gettext("Workflows that fit your team")}
            </p>
            <h2 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
              {gettext("Automate the next step, not the human judgment.")}
            </h2>
            <p class="mt-4 text-base leading-7 text-base-content/60">
              {gettext(
                "Start with a no-reply follow-up to prepare timely outreach, turn an incoming lead email into an owned task, or review an AI-drafted reply."
              )}
            </p>
            <div class="mt-7 space-y-4 text-sm leading-6 text-base-content/65">
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--message-2-check]" class="size-4" />
                </span>
                <p>
                  {gettext("No-reply follow-up prepares outreach when a customer has gone quiet.")}
                </p>
              </div>
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--checkbox]" class="size-4" />
                </span>
                <p>{gettext("Email to task turns an incoming lead email into owned work.")}</p>
              </div>
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--sparkles]" class="size-4" />
                </span>
                <p>
                  {gettext(
                    "AI email reply drafts a contextual response to each new customer email for your review."
                  )}
                </p>
              </div>
            </div>
          </div>
          <.workflow_demo />
        </div>
      </section>

      <section id="email-to-task-flow" class="border-t border-base-content/15">
        <div class="mx-auto grid max-w-7xl gap-10 px-5 py-20 sm:px-8 lg:grid-cols-[1.22fr_0.78fr] lg:items-center lg:px-10 lg:py-28">
          <div class="order-2 lg:order-none"><.email_to_task_demo /></div>
          <div class="order-1 max-w-xl lg:order-none lg:justify-self-end">
            <p class="text-sm font-semibold text-primary">{gettext("Email to task, end to end")}</p>
            <h2 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
              {gettext("Turn a customer request into work your team can see.")}
            </h2>
            <p class="mt-4 text-base leading-7 text-base-content/60">
              {gettext(
                "When a lead email includes several next steps, Konevo reads the thread, extracts the work, and puts each task where your team already plans its day."
              )}
            </p>
            <div class="mt-7 space-y-4 text-sm leading-6 text-base-content/65">
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--mail-opened]" class="size-4" />
                </span>
                <p>{gettext("A new email arrives with the customer’s requests and context.")}</p>
              </div>
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--sparkles]" class="size-4" />
                </span>
                <p>{gettext("AI identifies concrete next steps, owners, and due dates.")}</p>
              </div>
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--list-check]" class="size-4" />
                </span>
                <p>{gettext("Approved tasks appear in Tasks, ready to be owned and completed.")}</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section id="no-reply-follow-up-flow" class="border-t border-base-content/15">
        <div class="mx-auto grid max-w-7xl gap-10 px-5 py-20 sm:px-8 lg:grid-cols-[0.78fr_1.22fr] lg:items-center lg:px-10 lg:py-28">
          <div class="max-w-xl">
            <p class="text-sm font-semibold text-primary">
              {gettext("No-reply follow-up, end to end")}
            </p>
            <h2 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
              {gettext("Stay timely without sending a message too soon.")}
            </h2>
            <p class="mt-4 text-base leading-7 text-base-content/60">
              {gettext(
                "Choose the delay that fits your team. If a customer goes quiet, Konevo can prepare a thoughtful follow-up or send one automatically based on your workflow."
              )}
            </p>
            <div class="mt-7 space-y-4 text-sm leading-6 text-base-content/65">
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--clock-hour-4]" class="size-4" />
                </span>
                <p>{gettext("A quiet conversation reaches the delay you set.")}</p>
              </div>
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--mail-forward]" class="size-4" />
                </span>
                <p>{gettext("A follow-up is prepared with the thread’s context.")}</p>
              </div>
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--shield-check]" class="size-4" />
                </span>
                <p>{gettext("Choose whether it waits for review or sends automatically.")}</p>
              </div>
            </div>
          </div>
          <.no_reply_follow_up_demo />
        </div>
      </section>

      <section id="ai-email-reply-flow" class="border-t border-base-content/15">
        <div class="mx-auto grid max-w-7xl gap-10 px-5 py-20 sm:px-8 lg:grid-cols-[1.22fr_0.78fr] lg:items-center lg:px-10 lg:py-28">
          <div class="order-2 lg:order-none"><.ai_email_reply_demo /></div>
          <div class="order-1 max-w-xl lg:order-none lg:justify-self-end">
            <p class="text-sm font-semibold text-primary">{gettext("AI email reply, end to end")}</p>
            <h2 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
              {gettext("Reply faster while keeping your voice in the loop.")}
            </h2>
            <p class="mt-4 text-base leading-7 text-base-content/60">
              {gettext(
                "When a customer writes in, AI uses the conversation to prepare a clear response. You review the draft, adjust anything you need, and decide when to send."
              )}
            </p>
            <div class="mt-7 space-y-4 text-sm leading-6 text-base-content/65">
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--mail-opened]" class="size-4" />
                </span>
                <p>{gettext("A new customer email starts the workflow.")}</p>
              </div>
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--sparkles]" class="size-4" />
                </span>
                <p>{gettext("AI prepares a reply from the full conversation.")}</p>
              </div>
              <div class="flex gap-3">
                <span class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  <.icon name="icon-[tabler--edit]" class="size-4" />
                </span>
                <p>{gettext("The draft stays ready for your approval and edits.")}</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section id="technology" class="border-t border-base-content/15">
        <div class="mx-auto max-w-7xl px-5 py-20 sm:px-8 lg:px-10 lg:py-28">
          <div class="mx-auto max-w-2xl text-center">
            <p class="text-sm font-semibold text-primary">{gettext("What powers Konevo")}</p>
            <h2 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
              {gettext("Built around your inbox—and your control.")}
            </h2>
            <p class="mt-4 text-base leading-7 text-base-content/60">
              {gettext(
                "The right AI capability for each task, connected to the inbox your team already uses and built on principles you can trust."
              )}
            </p>
          </div>
          <div class="mt-12 grid gap-4 md:grid-cols-3">
            <.technology_card
              id="test-landing-provider-openai"
              icon="icon-[tabler--brand-openai]"
              title={gettext("OpenAI")}
              description={gettext("Used for standard and premium AI tasks.")}
              badge="GPT"
            />
            <.technology_card
              id="test-landing-provider-openai-models"
              icon="icon-[tabler--brain]"
              title={gettext("GPT-5.6 Terra & Luna")}
              description={
                gettext("Terra handles quality-focused work; Luna handles high-volume tasks.")
              }
              badge={gettext("Two models")}
            />
            <.technology_card
              id="test-landing-provider-gmail"
              icon="icon-[tabler--brand-gmail]"
              title={gettext("Gmail")}
              description={
                gettext("The first live integration, with inbox sync, history import, and replies.")
              }
              badge={gettext("Live")}
            />
          </div>
        </div>
      </section>

      <section id="installation" class="landing-section-tint border-t border-base-content/15">
        <div class="mx-auto max-w-7xl px-5 py-20 sm:px-8 lg:px-10 lg:py-28">
          <div class="mx-auto max-w-2xl text-center">
            <p class="text-sm font-semibold text-primary">{gettext("Installation")}</p>
            <h2 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
              {gettext("Get Konevo running on your server in three steps.")}
            </h2>
            <p class="mt-4 text-base leading-7 text-base-content/60">
              {gettext(
                "Bring a Linux server with Docker Compose and a domain pointed at it. Clone the deployment bundle once; it starts PostgreSQL and Caddy, provisions HTTPS automatically, and can optionally pull published release images."
              )}
            </p>
          </div>

          <div class="mx-auto mt-8 flex max-w-4xl items-start gap-3 rounded-2xl border border-primary/20 bg-primary/8 p-4 text-sm leading-6 text-base-content/70">
            <.icon name="icon-[tabler--info-circle]" class="mt-0.5 size-5 shrink-0 text-primary" />
            <div>
              <p class="font-semibold text-base-content">{gettext("Deployment model")}</p>
              <p class="mt-1">
                {gettext(
                  "Konevo is designed for one Linux server running Docker Compose. Kubernetes is not required or officially maintained; teams with multi-node or high-availability requirements can adapt the published container image to their own infrastructure."
                )}
              </p>
            </div>
          </div>

          <div class="mx-auto mt-8 flex max-w-4xl flex-col gap-5">
            <.installation_step
              id="installation-download"
              number="01"
              icon="icon-[tabler--download]"
              title={gettext("Clone the deployment bundle")}
              description={
                gettext(
                  "Create a restricted deployment account, then clone the repository. Do not download individual deployment files with curl."
                )
              }
            >
              <.installation_code_block
                id="installation-download-code"
                code={installation_download_commands()}
              />
            </.installation_step>

            <.installation_step
              id="installation-configure"
              number="02"
              icon="icon-[tabler--key]"
              title={gettext("Add your hostname and credentials")}
              description={
                gettext(
                  "Keep application settings and secrets only in the server environment file. Set APP_IMAGE to the published release you want to run; the public repository identifiers are needed only for automatic updates."
                )
              }
            >
              <.installation_code_block
                id="installation-configure-code"
                code={installation_configuration_commands()}
              />
            </.installation_step>

            <.installation_step
              id="installation-launch"
              number="03"
              icon="icon-[tabler--rocket]"
              title={gettext("Launch Konevo")}
              description={
                gettext(
                  "Start a chosen published release. Optionally install the release timer to automatically deploy the newest release without a GitHub SSH key."
                )
              }
            >
              <.installation_code_block
                id="installation-launch-code"
                code={installation_launch_commands()}
              />
            </.installation_step>
          </div>

          <div class="mx-auto mt-8 flex max-w-4xl items-start gap-3 rounded-2xl border border-primary/20 bg-primary/8 p-4 text-sm leading-6 text-base-content/70">
            <.icon name="icon-[tabler--info-circle]" class="mt-0.5 size-5 shrink-0 text-primary" />
            <p>
              {gettext(
                "Before launching, point your domain's DNS at the server and allow ports 80 and 443. Caddy requests and renews the TLS certificate; use the Gmail setup guide to add the matching OAuth redirect URL."
              )}
            </p>
          </div>
        </div>
      </section>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyInstallationCommand">
        export default {
          mounted() {
            this.copyIcon = this.el.querySelector("[data-copy-icon]")
            this.checkIcon = this.el.querySelector("[data-check-icon]")
            this.label = this.el.querySelector("[data-copy-label]")
            this.resetTimer = null
            this.onClick = () => this.copy()
            this.el.addEventListener("click", this.onClick)
          },
          async copy() {
            const source = document.getElementById(this.el.dataset.copyTarget)
            if (!source) return

            this.el.disabled = true

            try {
              await this.copyText(source.textContent)
              this.setStatus(this.el.dataset.copiedLabel, true)
            } catch (_error) {
              this.setStatus(this.el.dataset.copyErrorLabel, false)
            } finally {
              this.el.disabled = false
            }
          },
          async copyText(text) {
            if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(text)

            const input = document.createElement("textarea")
            input.value = text
            input.style.position = "fixed"
            input.style.opacity = "0"
            document.body.appendChild(input)
            input.select()
            const copied = document.execCommand("copy")
            input.remove()
            if (!copied) throw new Error("Clipboard unavailable")
          },
          setStatus(label, copied) {
            this.label.textContent = label
            this.el.setAttribute("aria-label", label)
            this.copyIcon.classList.toggle("hidden", copied)
            this.checkIcon.classList.toggle("hidden", !copied)
            window.clearTimeout(this.resetTimer)
            this.resetTimer = window.setTimeout(() => this.reset(), 2000)
          },
          reset() {
            this.label.textContent = this.el.dataset.copyLabel
            this.el.setAttribute("aria-label", this.el.dataset.copyLabel)
            this.copyIcon.classList.remove("hidden")
            this.checkIcon.classList.add("hidden")
          },
          destroyed() {
            window.clearTimeout(this.resetTimer)
            this.el.removeEventListener("click", this.onClick)
          }
        }
      </script>

      <section id="contact" class="landing-section-tint border-t border-base-content/15">
        <div class="mx-auto grid max-w-7xl gap-10 px-5 py-16 sm:px-8 lg:grid-cols-[.9fr_1.1fr] lg:items-center lg:px-10 lg:py-20">
          <div class="flex size-16 items-center justify-center rounded-2xl bg-primary/12 text-primary ring-1 ring-primary/20">
            <.icon name="icon-[tabler--message-circle-2]" class="size-8" />
          </div>
          <div>
            <p class="text-sm font-semibold text-primary">{gettext("Here to help")}</p>
            <h2 class="mt-3 text-3xl font-bold tracking-tight">
              {gettext("Questions or need help?")}
            </h2>
            <p class="mt-4 max-w-2xl leading-7 text-base-content/60">
              {gettext(
                "Have an idea, want to collaborate, or need help getting Konevo working for your team?"
              )}
              <span class="whitespace-nowrap">
                {gettext("Reach out at")}
                <a
                  href="mailto:filip.pauco08@gmail.com"
                  class="ml-1 font-medium text-primary underline decoration-primary/30 underline-offset-4 transition-colors hover:text-primary/75 hover:decoration-primary"
                >
                  filip.pauco08@gmail.com
                </a>.
              </span>
            </p>
            <div class="mt-7 flex flex-wrap gap-3">
              <a
                id="test-landing-contact-github"
                href="https://github.com/FilipPauco/konevo"
                target="_blank"
                rel="noreferrer"
                class="btn btn-primary btn-lg gap-2 shadow-none transition-transform duration-150 hover:shadow-none active:shadow-none sm:hover:-translate-y-0.5 motion-reduce:transform-none"
              >
                {gettext("View source")}
                <.icon name="icon-[tabler--brand-github]" class="size-5" />
              </a>
            </div>
          </div>
        </div>
      </section>

      <footer class="border-t border-base-content/15 px-5 py-5 sm:px-8 lg:px-10">
        <div class="mx-auto flex max-w-7xl items-center justify-center gap-3 text-center text-sm text-base-content/50">
          <span class="whitespace-nowrap">&copy; {Date.utc_today().year} Konevo</span>
          <span aria-hidden="true" class="size-1 shrink-0 rounded-full bg-current opacity-60" />
          <a
            id="test-landing-footer-privacy"
            href={~p"/privacy"}
            class="whitespace-nowrap transition-colors hover:text-primary"
          >
            {gettext("Privacy")}
          </a>
          <span aria-hidden="true" class="size-1 shrink-0 rounded-full bg-current opacity-60" />
          <a
            id="test-landing-footer-terms"
            href={~p"/terms"}
            class="whitespace-nowrap transition-colors hover:text-primary"
          >
            {gettext("Terms")}
          </a>
        </div>
      </footer>
      <Layouts.flash_group flash={@flash} />
    </main>
    """
  end

  attr(:icon, :string, required: true)
  attr(:label, :string, required: true)

  defp assurance(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5">
      <.icon name={@icon} class="size-4 text-primary" />{@label}
    </span>
    """
  end

  defp ai_draft_demo(assigns) do
    assigns =
      assign(
        assigns,
        :draft,
        gettext(
          "Hi Ava,\n\nThursday at 2:00 PM works perfectly for us. I've moved the kickoff and will send a calendar invite shortly.\n\nLooking forward to it,\nThe Konevo team"
        )
      )

    ~H"""
    <div
      id="ai-draft-demo"
      phx-hook=".AIDraftDemo"
      phx-update="ignore"
      data-draft={@draft}
      class="landing-product-demo overflow-hidden rounded-2xl border border-base-content/12 bg-base-100 shadow-2xl shadow-base-content/12"
    >
      <div class="flex items-center gap-2 border-b border-base-content/10 bg-base-200/55 px-4 py-3">
        <span class="flex size-6 items-center justify-center rounded-md bg-primary/10 text-primary">
          <.icon name="icon-[tabler--browser]" class="size-3.5" />
        </span>
        <div class="ml-1 flex h-6 flex-1 items-center rounded-md bg-base-100 px-2.5 text-[10px] text-base-content/40">
          konevo/inbox
        </div>
      </div>
      <div class="min-h-[29rem]">
        <div class="min-w-0 bg-base-100">
          <div class="flex items-center justify-between border-b border-base-content/10 px-4 py-3 sm:px-5">
            <div class="min-w-0">
              <p class="truncate text-xs font-semibold">{gettext("Re: onboarding timeline")}</p>
              <p class="mt-0.5 text-[10px] text-base-content/45">
                {gettext("Inbox · 1 conversation")}
              </p>
            </div>
            <span class="rounded-full bg-primary/10 px-2 py-1 text-[10px] font-medium text-primary">
              {gettext("Needs reply")}
            </span>
          </div>
          <div class="space-y-4 p-4 sm:p-5">
            <article class="rounded-xl border border-base-content/10 bg-base-100 p-3.5 shadow-sm">
              <div class="flex items-start justify-between gap-3">
                <div class="flex items-center gap-2.5">
                  <span class="flex size-8 items-center justify-center rounded-full bg-secondary/15 text-[11px] font-semibold text-secondary">
                    AS
                  </span>
                  <div>
                    <p class="text-xs font-semibold">Ava Simmons</p>
                    <p class="text-[10px] text-base-content/45">ava@acme.studio</p>
                  </div>
                </div>
                <time class="text-[10px] text-base-content/40">10:42</time>
              </div>
              <p class="mt-3 text-xs leading-5 text-base-content/70">
                {gettext("Could we move our kickoff to Thursday afternoon?")}
              </p>
            </article>

            <div class="rounded-xl border border-primary/20 bg-primary/5 p-3.5">
              <div class="flex items-center justify-between gap-3">
                <div class="flex items-center gap-2 text-xs font-semibold text-primary">
                  <.icon name="icon-[tabler--sparkles]" class="size-4" />
                  {gettext("Konevo AI")}
                </div>
                <span data-ai-status class="text-[10px] font-medium text-primary/75">
                  {gettext("Preparing draft")}
                </span>
              </div>
              <button
                id="ai-draft-demo-button"
                type="button"
                data-ai-draft
                class="ai-draft-demo-button mt-3 inline-flex h-7 items-center justify-center gap-1.5 rounded-md bg-primary px-2.5 text-[10px] font-semibold text-primary-content shadow-none transition-colors hover:bg-primary/90 hover:shadow-none active:shadow-none focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary/45"
              >
                <.icon name="icon-[tabler--sparkles]" class="size-3.5" />
                {gettext("Draft reply with AI")}
              </button>
            </div>

            <div class="rounded-xl border border-base-content/12 bg-base-100 shadow-sm">
              <div class="flex items-center justify-between border-b border-base-content/10 px-3.5 py-2.5">
                <span class="text-[10px] font-medium text-base-content/55">
                  {gettext("Replying to Ava")}
                </span>
                <.icon name="icon-[tabler--dots]" class="size-4 text-base-content/40" />
              </div>
              <div class="min-h-40 whitespace-pre-wrap px-3.5 py-3 text-xs leading-5 text-base-content/75">
                <span data-ai-content></span><span data-ai-caret class="ai-demo-caret">|</span>
              </div>
              <div class="flex items-center justify-between border-t border-base-content/10 px-3.5 py-2.5">
                <div class="flex gap-2 text-base-content/40">
                  <.icon name="icon-[tabler--paperclip]" class="size-4" />
                  <.icon name="icon-[tabler--mood-smile]" class="size-4" />
                </div>
                <span class="rounded-md bg-primary px-2.5 py-1 text-[10px] font-semibold text-primary-content">
                  {gettext("Send")}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AIDraftDemo">
      export default {
        mounted() {
          this.button = this.el.querySelector("[data-ai-draft]")
          this.status = this.el.querySelector("[data-ai-status]")
          this.output = this.el.querySelector("[data-ai-content]")
          this.caret = this.el.querySelector("[data-ai-caret]")
          this.draft = this.el.dataset.draft
          this.timers = []
          this.run = this.run.bind(this)
          this.button.addEventListener("click", this.run)

          this.observer = new IntersectionObserver(entries => {
            if (entries.some(entry => entry.isIntersecting)) {
              this.run()
              this.observer.disconnect()
            }
          }, {threshold: 0.35})
          this.observer.observe(this.el)
        },
        run() {
          this.stop()
          this.output.textContent = ""
          this.status.textContent = "Preparing draft"
          this.caret.classList.add("hidden")
          this.button.classList.remove("ai-draft-demo-button-press")
          void this.button.offsetWidth
          this.button.classList.add("ai-draft-demo-button-press")

          this.timers.push(setTimeout(() => {
            this.status.textContent = "Writing reply"
            this.caret.classList.remove("hidden")
            let index = 0
            const typeCharacter = () => {
              this.output.textContent = this.draft.slice(0, index)
              index += 1

              if (index <= this.draft.length) {
                this.timers.push(setTimeout(typeCharacter, 16))
              } else {
                this.status.textContent = "Draft ready"
                this.caret.classList.add("hidden")
                this.timers.push(setTimeout(this.run, 6200))
              }
            }
            typeCharacter()
          }, 700))
        },
        stop() {
          this.timers.forEach(timer => clearTimeout(timer))
          this.timers = []
        },
        destroyed() {
          this.stop()
          this.button.removeEventListener("click", this.run)
          this.observer.disconnect()
        }
      }
    </script>
    """
  end

  defp contact_extract_demo(assigns) do
    ~H"""
    <div
      id="contact-extract-demo"
      phx-hook=".ContactExtractDemo"
      phx-update="ignore"
      class="landing-product-demo overflow-hidden rounded-2xl border border-base-content/12 bg-base-100 shadow-2xl shadow-base-content/12"
    >
      <div class="flex items-center gap-2 border-b border-base-content/10 bg-base-200/55 px-4 py-3">
        <span class="flex size-6 items-center justify-center rounded-md bg-primary/10 text-primary">
          <.icon name="icon-[tabler--browser]" class="size-3.5" />
        </span>
        <div class="ml-1 flex h-6 flex-1 items-center rounded-md bg-base-100 px-2.5 text-[10px] text-base-content/40">
          konevo/inbox
        </div>
      </div>
      <div class="relative min-h-[18rem] overflow-hidden sm:min-h-[29rem]">
        <div
          data-extract-source
          class="grid min-h-[18rem] grid-cols-1 grid-rows-[auto_minmax(0,1fr)] sm:min-h-[29rem] sm:grid-cols-[minmax(0,1fr)_10.75rem] sm:grid-rows-1"
        >
          <div class="border-b border-base-content/10 p-3 sm:border-r sm:border-b-0 sm:p-5">
            <div class="flex items-start justify-between gap-3 border-b border-base-content/10 pb-3.5">
              <div class="flex min-w-0 items-center gap-2.5">
                <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-secondary/15 text-[11px] font-semibold text-secondary">
                  AS
                </span>
                <div class="min-w-0">
                  <p class="truncate text-xs font-semibold">Ava Simmons</p>
                  <p class="truncate text-[10px] text-base-content/45">ava@acme.studio</p>
                </div>
              </div>
              <time class="text-[10px] text-base-content/40">10:42</time>
            </div>
            <p class="mt-4 text-xs font-semibold">{gettext("Re: onboarding timeline")}</p>
            <p class="mt-3 text-xs leading-5 text-base-content/65">
              {gettext(
                "Hi there — I’m Ava from Acme Studio. Could we move our kickoff to Thursday afternoon?"
              )}
            </p>
          </div>
          <aside class="bg-base-200/30 p-3">
            <p class="text-[10px] font-semibold uppercase tracking-wider text-base-content/45">
              {gettext("Contact")}
            </p>
            <div class="mt-3 flex items-center gap-3 rounded-lg border border-base-content/10 bg-base-100 p-3 text-left sm:block sm:text-center">
              <.icon
                name="icon-[tabler--user-question]"
                class="size-6 shrink-0 text-base-content/25 sm:mx-auto"
              />
              <div class="min-w-0 flex-1">
                <p class="text-[10px] font-medium text-base-content/60 sm:mt-2">
                  {gettext("No contact linked")}
                </p>
                <div class="mt-2 grid grid-cols-1 gap-1.5 sm:mt-3 sm:block">
                  <button
                    id="contact-extract-demo-contact"
                    type="button"
                    data-extract-trigger="contact"
                    class="extract-demo-trigger btn btn-primary btn-xs w-full gap-1 whitespace-nowrap shadow-none hover:shadow-none active:shadow-none"
                  >
                    <.icon name="icon-[tabler--user-plus]" class="size-3" />
                    {gettext("Create contact")}
                  </button>
                  <button
                    id="contact-extract-demo-company"
                    type="button"
                    data-extract-trigger="company"
                    class="extract-demo-trigger btn btn-outline btn-xs mt-1.5 w-full gap-1 border-base-content/20 text-base-content/75 whitespace-nowrap shadow-none hover:border-base-content/30 hover:bg-base-200/70 hover:shadow-none active:shadow-none"
                  >
                    <.icon name="icon-[tabler--building-plus]" class="size-3" />
                    {gettext("Create company")}
                  </button>
                </div>
              </div>
            </div>
          </aside>
        </div>

        <div
          data-extract-form="contact"
          class="hidden absolute inset-0 z-10 flex items-center justify-center bg-base-100/85 p-2 sm:p-4"
        >
          <div class="w-full max-w-sm rounded-xl border border-base-content/15 bg-base-100 p-2.5 shadow-2xl shadow-base-content/20 sm:p-4">
            <div class="mb-2 flex items-start justify-between gap-3 sm:mb-4">
              <div class="flex items-center gap-2.5">
                <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                  <.icon name="icon-[tabler--user-plus]" class="size-4" />
                </span>
                <div>
                  <p class="text-xs font-semibold">{gettext("Create contact")}</p>
                  <p class="mt-0.5 text-[9px] text-base-content/50">
                    {gettext("Details found in this email")}
                  </p>
                </div>
              </div>
              <.icon name="icon-[tabler--x]" class="mt-1 size-4 text-base-content/40" />
            </div>
            <div class="mb-1.5 flex items-center gap-1.5 text-[9px] font-semibold uppercase tracking-wide text-base-content/45 sm:mb-2">
              <.icon name="icon-[tabler--user]" class="size-3" /> {gettext("Basic info")}
            </div>
            <div class="grid grid-cols-2 gap-1.5 rounded-xl border border-base-content/10 bg-base-200/30 p-2.5 sm:gap-2 sm:p-3">
              <.extract_demo_field label={gettext("First name")} value="Ava" />
              <.extract_demo_field label={gettext("Last name")} value="Simmons" />
              <.extract_demo_field label={gettext("Email")} value="ava@acme.studio" />
              <.extract_demo_field label={gettext("Phone")} value="+421 903 555 018" />
            </div>
            <div class="mt-2.5 flex justify-end gap-2 sm:mt-4">
              <span class="rounded-md border border-base-content/20 px-2.5 py-1.5 text-[10px] font-medium text-base-content/65">
                {gettext("Cancel")}
              </span>
              <span
                data-extract-save="contact"
                class="rounded-md bg-primary px-2.5 py-1.5 text-[10px] font-semibold text-primary-content"
              >
                {gettext("Save contact")}
              </span>
            </div>
          </div>
        </div>

        <div
          data-extract-form="company"
          class="hidden absolute inset-0 z-10 flex items-center justify-center bg-base-100/85 p-2 sm:p-4"
        >
          <div class="w-full max-w-sm rounded-xl border border-base-content/15 bg-base-100 p-2.5 shadow-2xl shadow-base-content/20 sm:p-4">
            <div class="mb-2 flex items-start justify-between gap-3 sm:mb-4">
              <div class="flex items-center gap-2.5">
                <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                  <.icon name="icon-[tabler--building-plus]" class="size-4" />
                </span>
                <div>
                  <p class="text-xs font-semibold">{gettext("Create company")}</p>
                  <p class="mt-0.5 text-[9px] text-base-content/50">
                    {gettext("Details found in this email")}
                  </p>
                </div>
              </div>
              <.icon name="icon-[tabler--x]" class="mt-1 size-4 text-base-content/40" />
            </div>
            <div class="mb-1.5 flex items-center gap-1.5 text-[9px] font-semibold uppercase tracking-wide text-base-content/45 sm:mb-2">
              <.icon name="icon-[tabler--building]" class="size-3" /> {gettext("Company profile")}
            </div>
            <div class="grid grid-cols-2 gap-1.5 rounded-xl border border-base-content/10 bg-base-200/30 p-2.5 sm:gap-2 sm:p-3">
              <.extract_demo_field label={gettext("Company name")} value="Acme Studio" />
              <.extract_demo_field label={gettext("Industry")} value={gettext("Creative agency")} />
              <.extract_demo_field label={gettext("Website")} value="acme.studio" />
              <.extract_demo_field label={gettext("Phone")} value="+421 903 555 018" />
            </div>
            <div class="mt-2.5 flex justify-end gap-2 sm:mt-4">
              <span class="rounded-md border border-base-content/20 px-2.5 py-1.5 text-[10px] font-medium text-base-content/65">
                {gettext("Cancel")}
              </span>
              <span
                data-extract-save="company"
                class="rounded-md bg-primary px-2.5 py-1.5 text-[10px] font-semibold text-primary-content"
              >
                {gettext("Save company")}
              </span>
            </div>
          </div>
        </div>

        <div
          data-extract-success
          class="hidden absolute top-4 right-4 z-20 rounded-lg border-2 border-primary bg-base-100 px-5 py-2.5 text-[10px] font-semibold text-primary shadow-none"
        >
          <span data-extract-success="contact" class="hidden items-center gap-2">
            <.icon name="icon-[tabler--check]" class="size-3.5" /> {gettext("Contact created")}
          </span>
          <span data-extract-success="company" class="hidden items-center gap-2">
            <.icon name="icon-[tabler--check]" class="size-3.5" /> {gettext("Company created")}
          </span>
        </div>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ContactExtractDemo">
      export default {
        mounted() {
          this.source = this.el.querySelector("[data-extract-source]")
          this.forms = this.el.querySelectorAll("[data-extract-form]")
          this.buttons = this.el.querySelectorAll("[data-extract-trigger]")
          this.success = this.el.querySelector("[data-extract-success]:not(span)")
          this.successMessages = this.el.querySelectorAll("span[data-extract-success]")
          this.timers = []
          this.run = this.run.bind(this)
          this.handlers = [...this.buttons].map(button => {
            const handler = () => this.run(button.dataset.extractTrigger)
            button.addEventListener("click", handler)
            return {button, handler}
          })

          this.observer = new IntersectionObserver(entries => {
            if (entries.some(entry => entry.isIntersecting)) {
              this.run("contact")
              this.observer.disconnect()
            }
          }, {threshold: 0.35})
          this.observer.observe(this.el)
        },
        run(kind) {
          this.stop()
          this.reset()
          const button = this.el.querySelector(`[data-extract-trigger="${kind}"]`)
          button.classList.remove("extract-demo-button-press")
          void button.offsetWidth
          button.classList.add("extract-demo-button-press")

          this.timers.push(setTimeout(() => this.showForm(kind), 1000))
        },
        reset() {
          this.source.classList.remove("hidden")
          this.forms.forEach(form => form.classList.add("hidden"))
          this.success.classList.add("hidden")
          this.successMessages.forEach(message => {
            message.classList.add("hidden")
            message.classList.remove("inline-flex")
          })
          this.el.querySelectorAll("[data-extract-field]").forEach(field => field.textContent = "")
        },
        showForm(kind) {
          this.source.classList.add("hidden")
          const form = this.el.querySelector(`[data-extract-form="${kind}"]`)
          form.classList.remove("hidden")
          const fields = [...form.querySelectorAll("[data-extract-field]")]
          this.fillField(fields, 0, kind)
        },
        fillField(fields, fieldIndex, kind) {
          if (fieldIndex >= fields.length) {
            this.timers.push(setTimeout(() => this.showSaved(kind), 900))
            return
          }

          const field = fields[fieldIndex]
          const value = field.dataset.value
          let characterIndex = 0
          const typeCharacter = () => {
            field.textContent = value.slice(0, characterIndex)
            characterIndex += 1

            if (characterIndex <= value.length) {
              this.timers.push(setTimeout(typeCharacter, 22))
            } else {
              this.timers.push(setTimeout(() => this.fillField(fields, fieldIndex + 1, kind), 120))
            }
          }
          typeCharacter()
        },
        showSaved(kind) {
          const save = this.el.querySelector(`[data-extract-save="${kind}"]`)
          save.classList.add("extract-demo-button-press")
          this.success.classList.remove("hidden")
          this.el.querySelector(`span[data-extract-success="${kind}"]`).classList.remove("hidden")
          this.el.querySelector(`span[data-extract-success="${kind}"]`).classList.add("inline-flex")
          const nextKind = kind === "contact" ? "company" : "contact"
          this.timers.push(setTimeout(() => this.run(nextKind), 3100))
        },
        stop() {
          this.timers.forEach(timer => clearTimeout(timer))
          this.timers = []
          this.buttons.forEach(button => button.classList.remove("extract-demo-button-press"))
        },
        destroyed() {
          this.stop()
          this.handlers.forEach(({button, handler}) => button.removeEventListener("click", handler))
          this.observer.disconnect()
        }
      }
    </script>
    """
  end

  defp no_reply_follow_up_demo(assigns) do
    ~H"""
    <div
      id="no-reply-follow-up-demo"
      class="landing-product-demo overflow-hidden rounded-2xl border border-base-content/12 bg-base-100 shadow-2xl shadow-base-content/12"
    >
      <div class="flex items-center gap-2 border-b border-base-content/10 bg-base-200/55 px-4 py-3">
        <span class="flex size-6 items-center justify-center rounded-md bg-primary/10 text-primary">
          <.icon name="icon-[tabler--browser]" class="size-3.5" />
        </span>
        <div class="ml-1 h-5 flex-1 rounded-md bg-base-100/75"></div>
      </div>
      <div class="min-h-[29rem] p-4 sm:p-5">
        <div class="border-b border-base-content/10 pb-3.5">
          <p class="text-xs font-semibold">{gettext("No-reply follow-up")}</p>
          <p class="mt-1 text-[10px] text-base-content/45">
            {gettext("Prepare or auto-send a follow-up")}
          </p>
        </div>

        <div class="mt-4 grid gap-3 lg:grid-cols-[1fr_.34fr_1fr]">
          <article class="rounded-xl border border-primary bg-base-200/25 p-3.5">
            <div class="flex items-center gap-2 text-[10px] font-semibold uppercase tracking-wider text-base-content/45">
              <span class="flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                1
              </span>
              {gettext("Customer conversation")}
            </div>
            <div class="mt-3 space-y-2.5 rounded-lg border border-base-content/10 bg-base-100 p-3 shadow-sm">
              <div class="flex items-center gap-2">
                <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-secondary/15 text-[9px] font-semibold text-secondary">
                  NR
                </span>
                <div>
                  <p class="text-[10px] font-semibold">Nora Reed</p>
                  <p class="text-[8px] text-base-content/45">{gettext("Monday · 10:42 AM")}</p>
                </div>
              </div>
              <p class="text-[10px] leading-4 text-base-content/60">
                {gettext("Thanks for the proposal. I’ll review it with the team this afternoon.")}
              </p>
              <div class="border-t border-base-content/8 pt-2.5">
                <p class="text-[9px] font-semibold text-primary">{gettext("You")}</p>
                <p class="mt-1 text-[10px] leading-4 text-base-content/60">
                  {gettext("Great—please let me know if any questions come up. I’m happy to help.")}
                </p>
              </div>
              <div class="flex items-center gap-1.5 rounded-md bg-warning/10 px-2 py-1.5 text-[8px] font-medium text-warning">
                <.icon name="icon-[tabler--clock-hour-4]" class="size-3" />
                {gettext("No reply for 2 days")}
              </div>
            </div>
          </article>

          <div class="flex min-h-24 items-center justify-center lg:min-h-0">
            <div class="flex flex-col items-center gap-2 text-center">
              <div class="flex flex-col items-center gap-1 text-[10px] font-semibold uppercase tracking-wider text-base-content/45">
                <span class="flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  2
                </span>
                <span class="max-w-20 leading-3">{gettext("Prepare or auto-send")}</span>
              </div>
              <span class="flex size-10 items-center justify-center rounded-xl border border-primary/20 bg-primary/8 text-primary shadow-sm">
                <.icon name="icon-[tabler--mail-forward]" class="size-5" />
              </span>
              <span class="hidden text-primary lg:block">→</span>
              <span class="text-primary lg:hidden">↓</span>
            </div>
          </div>

          <article class="rounded-xl border border-primary bg-base-200/25 p-3.5">
            <div class="flex items-center gap-2">
              <div class="flex items-center gap-2 text-[10px] font-semibold uppercase tracking-wider text-base-content/45">
                <span class="flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  3
                </span>
                {gettext("Follow-up message")}
              </div>
            </div>
            <div class="mt-3 rounded-lg border border-base-content/10 bg-base-100 p-3 shadow-sm">
              <p class="text-[8px] font-semibold uppercase tracking-wider text-base-content/45">
                {gettext("To · Nora Reed")}
              </p>
              <p class="mt-2 border-b border-base-content/8 pb-2 text-[10px] font-semibold">
                {gettext("Checking in on the proposal")}
              </p>
              <div class="mt-3 space-y-2 text-[10px] leading-4 text-base-content/60">
                <p>{gettext("Hi Nora,")}</p>
                <p>
                  {gettext(
                    "Just checking whether you had a chance to review the proposal with your team. I’m happy to answer questions or walk through anything together."
                  )}
                </p>
                <p>{gettext("Best, Filip")}</p>
              </div>
            </div>
          </article>
        </div>
      </div>
    </div>
    """
  end

  defp ai_email_reply_demo(assigns) do
    ~H"""
    <div
      id="ai-email-reply-demo"
      class="landing-product-demo overflow-hidden rounded-2xl border border-base-content/12 bg-base-100 shadow-2xl shadow-base-content/12"
    >
      <div class="flex items-center gap-2 border-b border-base-content/10 bg-base-200/55 px-4 py-3">
        <span class="flex size-6 items-center justify-center rounded-md bg-primary/10 text-primary">
          <.icon name="icon-[tabler--browser]" class="size-3.5" />
        </span>
        <div class="ml-1 h-5 flex-1 rounded-md bg-base-100/75"></div>
      </div>
      <div class="min-h-[29rem] p-4 sm:p-5">
        <div class="border-b border-base-content/10 pb-3.5">
          <p class="text-xs font-semibold">{gettext("AI email reply")}</p>
          <p class="mt-1 text-[10px] text-base-content/45">
            {gettext("A reply draft is ready for review")}
          </p>
        </div>

        <div class="mt-4 grid gap-3 lg:grid-cols-[0.85fr_0.38fr_1fr]">
          <article class="rounded-xl border border-primary bg-base-200/25 p-3.5">
            <div class="flex items-center justify-between gap-2">
              <div class="flex items-center gap-2 text-[10px] font-semibold uppercase tracking-wider text-base-content/45">
                <span class="flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  1
                </span>
                {gettext("New email")}
              </div>
              <span class="rounded-full bg-primary/10 px-1.5 py-0.5 text-[9px] font-medium text-primary">
                {gettext("New")}
              </span>
            </div>
            <div class="mt-3 rounded-lg border border-base-content/10 bg-base-100 p-3 shadow-sm">
              <div class="flex items-center gap-2">
                <span class="flex size-7 shrink-0 items-center justify-center rounded-full bg-secondary/15 text-[10px] font-semibold text-secondary">
                  LC
                </span>
                <div class="min-w-0">
                  <p class="truncate text-[11px] font-semibold">Liam Chen</p>
                  <p class="truncate text-[9px] text-base-content/45">liam@northstar.io</p>
                </div>
              </div>
              <p class="mt-3 text-[11px] font-semibold leading-4">
                {gettext("Question about onboarding")}
              </p>
              <div class="mt-2.5 space-y-2 text-[10px] leading-4 text-base-content/60">
                <p>{gettext("Hi Filip, we’re excited to get started next month.")}</p>
                <p>{gettext("Could you confirm what we need to prepare before the kickoff call?")}</p>
                <p>{gettext("Thanks, Liam")}</p>
              </div>
            </div>
          </article>

          <div class="flex min-h-24 items-center justify-center lg:min-h-0">
            <div class="flex flex-col items-center gap-2 text-center">
              <div class="flex flex-col items-center gap-1 text-[10px] font-semibold uppercase tracking-wider text-base-content/45">
                <span class="flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  2
                </span>
                <span class="max-w-24 leading-3">{gettext("AI prepares a reply")}</span>
              </div>
              <span class="flex size-10 items-center justify-center rounded-xl border border-primary/20 bg-primary/8 text-primary shadow-sm">
                <.icon name="icon-[tabler--sparkles]" class="size-5" />
              </span>
              <span class="hidden text-primary lg:block">→</span>
              <span class="text-primary lg:hidden">↓</span>
            </div>
          </div>

          <article class="rounded-xl border border-primary bg-base-200/25 p-3.5">
            <div class="flex items-center justify-between gap-2">
              <div class="flex items-center gap-2 text-[10px] font-semibold uppercase tracking-wider text-base-content/45">
                <span class="flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  3
                </span>
                {gettext("Review AI reply")}
              </div>
              <span class="rounded-full bg-primary/10 px-1.5 py-0.5 text-[9px] font-medium text-primary">
                {gettext("Ready to review")}
              </span>
            </div>
            <div class="mt-3 rounded-lg border border-base-content/10 bg-base-100 p-3 shadow-sm">
              <p class="text-[8px] font-semibold uppercase tracking-wider text-base-content/45">
                {gettext("Re: Question about onboarding")}
              </p>
              <div class="mt-3 space-y-2 text-[10px] leading-4 text-base-content/60">
                <p>{gettext("Hi Liam,")}</p>
                <p>
                  {gettext(
                    "Great to hear. Before our kickoff, please share your primary team contacts and the goals you would like to cover first. We’ll bring the implementation plan and guide the next steps."
                  )}
                </p>
                <p>{gettext("Best, Filip")}</p>
              </div>
            </div>
          </article>
        </div>
      </div>
    </div>
    """
  end

  defp email_to_task_demo(assigns) do
    ~H"""
    <div
      id="email-to-task-demo"
      phx-hook=".EmailToTaskDemo"
      phx-update="ignore"
      data-waiting={gettext("New email received")}
      data-extracting={gettext("AI is extracting tasks")}
      data-created={gettext("4 tasks created in Tasks")}
      class="landing-product-demo overflow-hidden rounded-2xl border border-base-content/12 bg-base-100 shadow-2xl shadow-base-content/12"
    >
      <div class="flex items-center gap-2 border-b border-base-content/10 bg-base-200/55 px-4 py-3">
        <span class="flex size-6 items-center justify-center rounded-md bg-primary/10 text-primary">
          <.icon name="icon-[tabler--browser]" class="size-3.5" />
        </span>
        <div class="ml-1 flex h-6 flex-1 items-center rounded-md bg-base-100 px-2.5 text-[10px] text-base-content/40">
          konevo/inbox → tasks
        </div>
      </div>

      <div class="min-h-[29rem] p-4 sm:p-5">
        <div class="border-b border-base-content/10 pb-3.5">
          <div>
            <p class="text-xs font-semibold">{gettext("Email to task")}</p>
            <p data-email-task-status class="mt-1 text-[10px] text-base-content/45">
              {gettext("New email received")}
            </p>
          </div>
        </div>

        <div class="mt-4 grid gap-3 lg:grid-cols-[0.85fr_0.38fr_1fr]">
          <article
            data-email-task-email
            class="rounded-xl border border-base-content/10 bg-base-200/25 p-3.5 transition-all duration-300"
          >
            <div class="flex items-center justify-between gap-2">
              <div class="flex items-center gap-2 text-[10px] font-semibold uppercase tracking-wider text-base-content/45">
                <span class="flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  1
                </span>
                {gettext("You receive an email")}
              </div>
              <span class="rounded-full bg-primary/10 px-1.5 py-0.5 text-[9px] font-medium text-primary">
                {gettext("New")}
              </span>
            </div>
            <div class="mt-3 rounded-lg border border-base-content/10 bg-base-100 p-3 shadow-sm">
              <div class="flex items-center gap-2">
                <span class="flex size-7 shrink-0 items-center justify-center rounded-full bg-secondary/15 text-[10px] font-semibold text-secondary">
                  NR
                </span>
                <div class="min-w-0">
                  <p class="truncate text-[11px] font-semibold">Nora Reed</p>
                  <p class="truncate text-[9px] text-base-content/45">nora@northstar.io</p>
                </div>
              </div>
              <p class="mt-3 text-[11px] font-semibold leading-4">
                {gettext("Planning our Q4 rollout")}
              </p>
              <div class="mt-2.5 space-y-2 text-[10px] leading-4 text-base-content/60">
                <p>{gettext("Hi team, we’re ready to plan the next phase with you.")}</p>
                <p>
                  {gettext(
                    "Could you send pricing for 25 seats by Friday and confirm a 45-minute kickoff on Tuesday? We would also like a tailored product demo and an implementation timeline."
                  )}
                </p>
                <p>{gettext("Thanks, Nora")}</p>
              </div>
            </div>
          </article>

          <div class="flex min-h-24 items-center justify-center lg:min-h-0">
            <div data-email-task-engine class="flex flex-col items-center gap-2 text-center">
              <div class="flex flex-col items-center gap-1 text-[10px] font-semibold uppercase tracking-wider text-base-content/45">
                <span class="flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/12 text-primary">
                  2
                </span>
                <span class="max-w-24 leading-3">{gettext("Tasks are auto-extracted")}</span>
              </div>
              <span class="email-task-demo-engine flex size-10 items-center justify-center rounded-xl border border-primary/20 bg-primary/8 text-primary shadow-sm">
                <.icon name="icon-[tabler--sparkles]" class="size-5" />
              </span>
              <span class="hidden text-primary lg:block">→</span>
              <span class="text-primary lg:hidden">↓</span>
            </div>
          </div>

          <article class="email-task-demo-tasks-active rounded-xl border border-base-content/10 bg-base-200/25 p-3.5">
            <div class="flex items-center justify-between gap-2">
              <div class="flex items-center gap-2 text-[10px] font-semibold uppercase tracking-wider text-base-content/45">
                <span class="flex size-5 items-center justify-center rounded-full bg-primary/12 text-primary">
                  3
                </span>
                {gettext("Task added to your task list")}
              </div>
              <span
                data-email-task-count
                class="rounded-full bg-base-100 px-1.5 py-0.5 text-[9px] font-medium text-base-content/45"
              >
                0
              </span>
            </div>
            <div class="mt-3 overflow-hidden rounded-lg border border-base-content/10 bg-base-100">
              <div class="grid grid-cols-[minmax(0,1fr)_auto] border-b border-base-content/10 bg-base-200/45 px-2.5 py-1.5 text-[8px] font-semibold uppercase tracking-wider text-base-content/45">
                <span>{gettext("Task")}</span>
                <span>{gettext("Status")}</span>
              </div>
              <div
                data-email-task-epic
                class="hidden grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 border-b border-base-content/10 bg-warning/4 px-2.5 py-2"
              >
                <div class="flex min-w-0 items-center gap-1.5">
                  <span class="flex size-4 shrink-0 items-center justify-center rounded bg-primary/10 text-primary">
                    <.icon name="icon-[tabler--chevron-down]" class="size-3" />
                  </span>
                  <span class="flex size-5 shrink-0 items-center justify-center rounded-md border border-warning/45 bg-warning/10 text-warning">
                    <.icon name="icon-[tabler--crown]" class="size-3" />
                  </span>
                  <span class="truncate text-[10px] font-semibold">
                    {gettext("Company - Northstar")}
                  </span>
                  <.icon
                    name="icon-[tabler--dots-vertical]"
                    class="ml-auto size-3 text-base-content/35"
                  />
                </div>
                <span class="inline-flex items-center gap-1 rounded-md border border-[#0ea5e9]/35 bg-[#0ea5e9]/12 px-1.5 py-0.5 text-[8px] font-medium text-[#0ea5e9]">
                  <.icon name="icon-[tabler--circle]" class="size-2.5" /> {gettext("Open")}
                </span>
              </div>
              <div
                data-email-task-card
                class="hidden grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 border-b border-base-content/10 px-2.5 py-2"
              >
                <div class="flex min-w-0 items-center gap-1.5 pl-5">
                  <span class="flex size-5 shrink-0 items-center justify-center rounded-md border border-primary/35 bg-primary/8 text-primary">
                    <.icon name="icon-[tabler--menu-2]" class="size-3" />
                  </span>
                  <span class="truncate text-[10px] font-semibold">
                    {gettext("Send pricing for 25 seats")}
                  </span>
                  <.icon
                    name="icon-[tabler--dots-vertical]"
                    class="ml-auto size-3 text-base-content/35"
                  />
                </div>
                <span class="inline-flex items-center gap-1 rounded-md border border-[#0ea5e9]/35 bg-[#0ea5e9]/12 px-1.5 py-0.5 text-[8px] font-medium text-[#0ea5e9]">
                  <.icon name="icon-[tabler--circle]" class="size-2.5" /> {gettext("Open")}
                </span>
              </div>
              <div
                data-email-task-card
                class="hidden grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 border-b border-base-content/10 px-2.5 py-2"
              >
                <div class="flex min-w-0 items-center gap-1.5 pl-5">
                  <span class="flex size-5 shrink-0 items-center justify-center rounded-md border border-primary/35 bg-primary/8 text-primary">
                    <.icon name="icon-[tabler--menu-2]" class="size-3" />
                  </span>
                  <span class="truncate text-[10px] font-semibold">
                    {gettext("Confirm Tuesday’s kickoff")}
                  </span>
                  <.icon
                    name="icon-[tabler--dots-vertical]"
                    class="ml-auto size-3 text-base-content/35"
                  />
                </div>
                <span class="inline-flex items-center gap-1 rounded-md border border-[#0ea5e9]/35 bg-[#0ea5e9]/12 px-1.5 py-0.5 text-[8px] font-medium text-[#0ea5e9]">
                  <.icon name="icon-[tabler--circle]" class="size-2.5" /> {gettext("Open")}
                </span>
              </div>
              <div
                data-email-task-card
                class="hidden grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 border-b border-base-content/10 px-2.5 py-2"
              >
                <div class="flex min-w-0 items-center gap-1.5 pl-5">
                  <span class="flex size-5 shrink-0 items-center justify-center rounded-md border border-primary/35 bg-primary/8 text-primary">
                    <.icon name="icon-[tabler--menu-2]" class="size-3" />
                  </span>
                  <span class="truncate text-[10px] font-semibold">
                    {gettext("Prepare Northstar demo")}
                  </span>
                  <.icon
                    name="icon-[tabler--dots-vertical]"
                    class="ml-auto size-3 text-base-content/35"
                  />
                </div>
                <span class="inline-flex items-center gap-1 rounded-md border border-[#0ea5e9]/35 bg-[#0ea5e9]/12 px-1.5 py-0.5 text-[8px] font-medium text-[#0ea5e9]">
                  <.icon name="icon-[tabler--circle]" class="size-2.5" /> {gettext("Open")}
                </span>
              </div>
              <div
                data-email-task-card
                class="hidden grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 px-2.5 py-2"
              >
                <div class="flex min-w-0 items-center gap-1.5 pl-5">
                  <span class="flex size-5 shrink-0 items-center justify-center rounded-md border border-primary/35 bg-primary/8 text-primary">
                    <.icon name="icon-[tabler--menu-2]" class="size-3" />
                  </span>
                  <span class="truncate text-[10px] font-semibold">
                    {gettext("Share implementation timeline")}
                  </span>
                  <.icon
                    name="icon-[tabler--dots-vertical]"
                    class="ml-auto size-3 text-base-content/35"
                  />
                </div>
                <span class="inline-flex items-center gap-1 rounded-md border border-[#0ea5e9]/35 bg-[#0ea5e9]/12 px-1.5 py-0.5 text-[8px] font-medium text-[#0ea5e9]">
                  <.icon name="icon-[tabler--circle]" class="size-2.5" /> {gettext("Open")}
                </span>
              </div>
            </div>
          </article>
        </div>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".EmailToTaskDemo">
      export default {
        mounted() {
          this.status = this.el.querySelector("[data-email-task-status]")
          this.email = this.el.querySelector("[data-email-task-email]")
          this.engine = this.el.querySelector("[data-email-task-engine]")
          this.count = this.el.querySelector("[data-email-task-count]")
          this.epic = this.el.querySelector("[data-email-task-epic]")
          this.cards = this.el.querySelectorAll("[data-email-task-card]")
          this.timers = []
          this.run = this.run.bind(this)

          this.observer = new IntersectionObserver(entries => {
            if (entries.some(entry => entry.isIntersecting)) {
              this.run()
              this.observer.disconnect()
            }
          }, {threshold: 0.3})
          this.observer.observe(this.el)
        },
        reset() {
          this.timers.forEach(timer => clearTimeout(timer))
          this.timers = []
          this.status.textContent = this.el.dataset.waiting
          this.count.textContent = "0"
          this.email.classList.remove("email-task-demo-email-active")
          this.engine.classList.remove("email-task-demo-engine-active")
          this.epic.classList.add("hidden")
          this.epic.classList.remove("email-task-demo-task-enter")
          this.cards.forEach(card => {
            card.classList.add("hidden")
            card.classList.remove("email-task-demo-task-enter")
          })
        },
        run() {
          this.reset()
          this.email.classList.add("email-task-demo-email-active")
          this.timers.push(setTimeout(() => {
            this.status.textContent = this.el.dataset.extracting
            this.engine.classList.add("email-task-demo-engine-active")
          }, 750))
          this.timers.push(setTimeout(() => {
            this.epic.classList.remove("hidden")
            this.epic.classList.add("email-task-demo-task-enter")
          }, 1400))
          this.cards.forEach((card, index) => {
            this.timers.push(setTimeout(() => {
              card.classList.remove("hidden")
              card.classList.add("email-task-demo-task-enter")
              this.count.textContent = String(index + 1)
            }, 1800 + index * 430))
          })
          this.timers.push(setTimeout(() => {
            this.status.textContent = this.el.dataset.created
            this.engine.classList.remove("email-task-demo-engine-active")
          }, 3400))
          this.timers.push(setTimeout(this.run, 8000))
        },
        destroyed() {
          this.timers.forEach(timer => clearTimeout(timer))
          this.observer.disconnect()
        }
      }
    </script>
    """
  end

  defp workflow_demo(assigns) do
    ~H"""
    <div
      id="workflow-demo"
      phx-hook=".WorkflowDemo"
      phx-update="ignore"
      class="landing-product-demo overflow-hidden rounded-2xl border border-base-content/12 bg-base-100 shadow-2xl shadow-base-content/12"
    >
      <div class="flex items-center gap-2 border-b border-base-content/10 bg-base-200/55 px-4 py-3">
        <span class="flex size-6 items-center justify-center rounded-md bg-primary/10 text-primary">
          <.icon name="icon-[tabler--browser]" class="size-3.5" />
        </span>
        <div class="ml-1 flex h-6 flex-1 items-center rounded-md bg-base-100 px-2.5 text-[10px] text-base-content/40">
          konevo/workflows
        </div>
      </div>
      <div class="min-h-[29rem] p-4 sm:p-5">
        <div class="flex items-start justify-between border-b border-base-content/10 pb-3.5">
          <div>
            <p class="text-xs font-semibold">{gettext("Workflow templates")}</p>
            <p class="mt-1 text-[10px] text-base-content/45">{gettext("3 types ready to use")}</p>
          </div>
          <span class="rounded-full bg-primary/10 px-2 py-1 text-[10px] font-medium text-primary">
            {gettext("On")}
          </span>
        </div>

        <div class="mt-4 grid gap-4 sm:grid-cols-[0.78fr_1.22fr]">
          <article class="rounded-xl border border-primary bg-base-200/25 p-3.5">
            <div class="flex items-center gap-2 text-[10px] font-semibold uppercase tracking-wider text-base-content/45">
              <span class="flex size-5 items-center justify-center rounded-full bg-primary/12 text-primary">
                1
              </span>
              {gettext("Choose workflow type")}
            </div>
            <div class="mt-3 space-y-2">
              <button
                id="workflow-demo-manual"
                type="button"
                data-workflow-mode="manual"
                class="workflow-demo-mode w-full rounded-lg border border-base-content/10 bg-base-100 p-3 text-left shadow-none transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary/45"
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="text-[11px] font-semibold">{gettext("No-reply follow-up")}</span>
                  <span class="workflow-demo-mode-dot size-2 rounded-full border border-base-content/25" />
                </div>
                <p class="mt-1.5 text-[10px] leading-4 text-base-content/50">
                  {gettext("Prepare outreach after a customer has not replied.")}
                </p>
              </button>
              <button
                id="workflow-demo-automatic"
                type="button"
                data-workflow-mode="automatic"
                class="workflow-demo-mode w-full rounded-lg border border-base-content/10 bg-base-100 p-3 text-left shadow-none transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary/45"
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="text-[11px] font-semibold">{gettext("Email to task")}</span>
                  <span class="workflow-demo-mode-dot size-2 rounded-full border border-base-content/25" />
                </div>
                <p class="mt-1.5 text-[10px] leading-4 text-base-content/50">
                  {gettext("Turn a new lead email into an owned task.")}
                </p>
              </button>
              <button
                id="workflow-demo-reply"
                type="button"
                data-workflow-mode="reply"
                class="workflow-demo-mode w-full rounded-lg border border-base-content/10 bg-base-100 p-3 text-left shadow-none transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary/45"
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="text-[11px] font-semibold">{gettext("AI email reply")}</span>
                  <span class="workflow-demo-mode-dot size-2 rounded-full border border-base-content/25" />
                </div>
                <p class="mt-1.5 text-[10px] leading-4 text-base-content/50">
                  {gettext("Draft a contextual reply for review.")}
                </p>
              </button>
            </div>
          </article>

          <article class="rounded-xl border border-primary bg-base-200/25 p-3.5">
            <div class="flex items-center gap-2 text-[10px] font-semibold uppercase tracking-wider text-base-content/45">
              <span class="flex size-5 items-center justify-center rounded-full bg-primary/12 text-primary">
                2
              </span>
              {gettext("Configure workflow")}
            </div>

            <div data-workflow-config="manual" class="workflow-demo-task mt-3 space-y-2.5">
              <p class="text-[11px] font-semibold">{gettext("No-reply follow-up")}</p>
              <div class="grid gap-2 sm:grid-cols-3">
                <.workflow_demo_field
                  label={gettext("Trigger")}
                  value={gettext("No reply after delay")}
                />
                <.workflow_demo_field label={gettext("Wait")} value={gettext("2 days")} />
                <.workflow_demo_field label={gettext("Action")} value={gettext("Prepare follow-up")} />
              </div>
              <div class="flex items-center gap-2 rounded-md bg-primary/8 px-2.5 py-2 text-[9px] text-primary">
                <.icon name="icon-[tabler--shield-check]" class="size-3.5" />
                {gettext("Manual review required before sending")}
              </div>
            </div>

            <div data-workflow-config="automatic" class="workflow-demo-task mt-3 hidden space-y-2.5">
              <p class="text-[11px] font-semibold">{gettext("Email to task")}</p>
              <div class="grid gap-2 sm:grid-cols-3">
                <.workflow_demo_field label={gettext("Trigger")} value={gettext("Email arrives")} />
                <.workflow_demo_field label={gettext("Action")} value={gettext("Extract tasks")} />
                <.workflow_demo_field label={gettext("Result")} value={gettext("Review suggestions")} />
              </div>
              <div class="flex items-center gap-2 rounded-md bg-primary/8 px-2.5 py-2 text-[9px] text-primary">
                <.icon name="icon-[tabler--shield-check]" class="size-3.5" />
                {gettext("Tasks are created only after approval")}
              </div>
            </div>

            <div data-workflow-config="reply" class="workflow-demo-task mt-3 hidden space-y-2.5">
              <p class="text-[11px] font-semibold">{gettext("AI email reply")}</p>
              <div class="grid gap-2 sm:grid-cols-3">
                <.workflow_demo_field label={gettext("Trigger")} value={gettext("Email arrives")} />
                <.workflow_demo_field label={gettext("Action")} value={gettext("Prepare AI reply")} />
                <.workflow_demo_field label={gettext("Result")} value={gettext("Review draft")} />
              </div>
              <div class="flex items-center gap-2 rounded-md bg-primary/8 px-2.5 py-2 text-[9px] text-primary">
                <.icon name="icon-[tabler--shield-check]" class="size-3.5" />
                {gettext("AI replies are never sent automatically")}
              </div>
            </div>

            <div class="mt-3 text-[10px] font-medium text-primary">
              <span data-workflow-status="manual">{gettext("No-reply follow-up selected")}</span>
              <span data-workflow-status="automatic" class="hidden">
                {gettext("Email to task selected")}
              </span>
              <span data-workflow-status="reply" class="hidden">
                {gettext("AI email reply selected")}
              </span>
            </div>
          </article>
        </div>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".WorkflowDemo">
      export default {
        mounted() {
          this.modes = this.el.querySelectorAll("[data-workflow-mode]")
          this.statuses = this.el.querySelectorAll("[data-workflow-status]")
          this.configs = this.el.querySelectorAll("[data-workflow-config]")
          this.timers = []
          this.play = this.play.bind(this)
          this.handlers = [...this.modes].map(mode => {
            const handler = () => this.play(mode.dataset.workflowMode)
            mode.addEventListener("click", handler)
            return {mode, handler}
          })

          this.observer = new IntersectionObserver(entries => {
            if (entries.some(entry => entry.isIntersecting)) {
              this.play("manual")
              this.observer.disconnect()
            }
          }, {threshold: 0.35})
          this.observer.observe(this.el)
        },
        play(mode) {
          this.timers.forEach(timer => clearTimeout(timer))
          this.timers = []
          this.modes.forEach(item => item.classList.toggle("workflow-demo-mode-active", item.dataset.workflowMode === mode))
          this.statuses.forEach(status => status.classList.toggle("hidden", status.dataset.workflowStatus !== mode))
          const config = [...this.configs].find(item => item.dataset.workflowConfig === mode)
          this.configs.forEach(item => item.classList.toggle("hidden", item !== config))
          config.classList.remove("workflow-demo-task-enter")
          void config.offsetWidth
          config.classList.add("workflow-demo-task-enter")
          const modes = ["manual", "automatic", "reply"]
          const nextMode = modes[(modes.indexOf(mode) + 1) % modes.length]
          this.timers.push(setTimeout(() => this.play(nextMode), 5100))
        },
        destroyed() {
          this.timers.forEach(timer => clearTimeout(timer))
          this.handlers.forEach(({mode, handler}) => mode.removeEventListener("click", handler))
          this.observer.disconnect()
        }
      }
    </script>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)

  defp workflow_demo_field(assigns) do
    ~H"""
    <div class="rounded-md border border-base-content/10 bg-base-100 px-2.5 py-2">
      <p class="text-[8px] font-semibold uppercase tracking-wider text-base-content/45">{@label}</p>
      <p class="mt-1 text-[10px] font-medium text-base-content/70">{@value}</p>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)

  defp extract_demo_field(assigns) do
    ~H"""
    <div>
      <p class="mb-0.5 text-[9px] font-medium text-base-content/50 sm:mb-1 sm:text-[10px]">
        {@label}
      </p>
      <div class="flex h-7 items-center rounded-md border border-base-content/20 bg-base-100 px-2 text-[9px] text-base-content/75 sm:h-8 sm:rounded-lg sm:px-2.5 sm:text-[10px]">
        <span data-extract-field data-value={@value}></span>
      </div>
    </div>
    """
  end

  attr(:active_page, :string, required: true)

  defp product_preview(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-2xl border border-base-content/12 bg-base-100 shadow-xl shadow-base-content/14 transition-all duration-300 sm:shadow-2xl sm:shadow-base-content/15">
      <div class="hidden items-center gap-2 border-b border-base-content/10 bg-base-200/50 px-4 py-3 sm:flex">
        <span class="flex size-6 items-center justify-center rounded-md bg-primary/10 text-primary">
          <.icon name="icon-[tabler--browser]" class="size-3.5" />
        </span>
        <div class="ml-1 flex h-6 flex-1 items-center rounded-md bg-base-100 px-2.5 text-[10px] text-base-content/40">
          konevo/{@active_page}
        </div>
      </div>
      <div class="sm:hidden">
        <.mobile_product_preview page={@active_page} />
      </div>
      <div class="product-preview-surface pointer-events-none relative hidden h-[31rem] grid-cols-[9.5rem_minmax(0,1fr)] sm:grid">
        <aside class="hidden border-r border-base-content/10 bg-base-200/35 p-3 sm:block">
          <div class="mb-6 hidden items-center gap-2 px-2 sm:flex">
            <img
              src={~p"/images/logo-navbar-v2.png"}
              alt=""
              class="size-7 object-contain"
            />
            <span class="text-xs font-bold">Konevo</span>
          </div>
          <nav class="space-y-1" aria-label={gettext("Product preview navigation")}>
            <.preview_nav
              page="dashboard"
              icon="icon-[tabler--layout-dashboard]"
              label={gettext("Dashboard")}
              active_page={@active_page}
            />
            <.preview_nav
              page="inbox"
              icon="icon-[tabler--inbox]"
              label={gettext("Inbox")}
              badge="8"
              active_page={@active_page}
            />
            <.preview_nav
              page="contacts"
              icon="icon-[tabler--users]"
              label={gettext("Contacts")}
              active_page={@active_page}
            />
            <.preview_nav
              page="companies"
              icon="icon-[tabler--building]"
              label={gettext("Companies")}
              active_page={@active_page}
            />
            <.preview_nav
              page="deals"
              icon="icon-[tabler--briefcase]"
              label={gettext("Deals")}
              active_page={@active_page}
            />
            <.preview_nav
              page="calendar"
              icon="icon-[tabler--calendar-week]"
              label={gettext("Calendar")}
              active_page={@active_page}
            />
            <.preview_nav
              page="tasks"
              icon="icon-[tabler--checkbox]"
              label={gettext("Tasks")}
              active_page={@active_page}
            />
          </nav>
        </aside>
        <div
          id="test-landing-preview-screen"
          phx-hook=".PreviewTransition"
          data-preview-page={@active_page}
          class="min-w-0 overflow-hidden p-3 sm:p-5"
        >
          <.preview_workspace page={@active_page} />
        </div>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PreviewTransition">
      export default {
        mounted() {
          this.page = this.el.dataset.previewPage
        },
        beforeUpdate() {
          if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

          this.removeSnapshot()
          const container = this.el.parentElement
          const snapshot = this.el.cloneNode(true)

          snapshot.removeAttribute("id")
          snapshot.removeAttribute("phx-hook")
          snapshot.querySelectorAll("[id], [phx-hook]").forEach(node => {
            node.removeAttribute("id")
            node.removeAttribute("phx-hook")
          })
          snapshot.setAttribute("aria-hidden", "true")
          snapshot.classList.remove("product-preview-enter")
          snapshot.classList.add("product-preview-exit")
          Object.assign(snapshot.style, {
            position: "absolute",
            left: `${this.el.offsetLeft}px`,
            top: `${this.el.offsetTop}px`,
            width: `${this.el.offsetWidth}px`,
            height: `${this.el.offsetHeight}px`,
            margin: "0",
            pointerEvents: "none",
            zIndex: "10"
          })

          container.appendChild(snapshot)
          this.snapshot = snapshot
        },
        updated() {
          const page = this.el.dataset.previewPage

          if (page === this.page) {
            this.removeSnapshot()
            return
          }

          this.page = page
          this.play()
        },
        play() {
          if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
          this.el.classList.remove("product-preview-enter")
          void this.el.offsetWidth
          this.el.classList.add("product-preview-enter")

          if (this.snapshot) {
            requestAnimationFrame(() => {
              this.snapshot?.classList.add("product-preview-exit-active")
              this.snapshot?.addEventListener("animationend", () => this.removeSnapshot(), {once: true})
            })
          }
        },
        removeSnapshot() {
          this.snapshot?.remove()
          this.snapshot = null
        },
        destroyed() {
          this.removeSnapshot()
        }
      }
    </script>
    """
  end

  attr(:page, :string, required: true)

  defp preview_workspace(assigns) do
    ~H"""
    <%= case @page do %>
      <% "inbox" -> %>
        <.inbox_preview />
      <% "contacts" -> %>
        <.contacts_preview />
      <% "companies" -> %>
        <.companies_preview />
      <% "deals" -> %>
        <.deals_preview />
      <% "calendar" -> %>
        <.calendar_preview />
      <% "tasks" -> %>
        <.tasks_preview />
      <% _ -> %>
        <.home_preview />
    <% end %>
    """
  end

  attr(:page, :string, required: true)

  defp mobile_product_preview(assigns) do
    ~H"""
    <div class="h-[24rem] overflow-hidden bg-base-200/35">
      <header class="relative flex h-12 items-center justify-between border-b border-base-content/20 bg-base-100 px-3">
        <span class="btn btn-ghost btn-sm btn-square">
          <.icon name="icon-[tabler--menu-2]" class="size-4" />
        </span>
        <div class="absolute left-1/2 flex h-7 w-36 -translate-x-1/2 items-center gap-1.5 rounded-lg border border-base-content/10 bg-base-200/35 px-2 text-[9px] text-base-content/40">
          <.icon name="icon-[tabler--search]" class="size-3" />{gettext("Search")}
        </div>
        <span class="flex size-7 items-center justify-center rounded-full bg-primary/12 text-[9px] font-bold text-primary">
          FP
        </span>
      </header>
      <div class="h-[calc(100%-3rem)] overflow-hidden p-3">
        <%= case @page do %>
          <% "inbox" -> %>
            <.mobile_inbox_preview />
          <% "contacts" -> %>
            <.mobile_contacts_preview />
          <% "companies" -> %>
            <.mobile_companies_preview />
          <% "deals" -> %>
            <.mobile_deals_preview />
          <% "calendar" -> %>
            <.mobile_calendar_preview />
          <% "tasks" -> %>
            <.mobile_tasks_preview />
          <% _ -> %>
            <.mobile_home_preview />
        <% end %>
      </div>
    </div>
    """
  end

  defp mobile_home_preview(assigns) do
    ~H"""
    <div class="flex items-end justify-between">
      <div>
        <p class="text-[10px] font-medium text-base-content/45">Tuesday, 12 March</p>
        <h2 class="mt-0.5 text-lg font-bold">Good morning, Filip</h2>
      </div>
      <span class="flex size-8 items-center justify-center rounded-lg bg-primary/10 text-primary">
        <.icon name="icon-[tabler--sparkles]" class="size-4" />
      </span>
    </div>
    <div class="mt-3 grid grid-cols-2 gap-2">
      <.mobile_preview_metric value="8" label={gettext("Need reply")} tone="warning" />
      <.mobile_preview_metric value="5" label={gettext("Tasks due")} tone="primary" />
      <.mobile_preview_metric value="€12k" label={gettext("At risk")} tone="error" />
      <.mobile_preview_metric value="3" label={gettext("Closing soon")} tone="success" />
    </div>
    <div class="mt-4 flex items-center justify-between">
      <h3 class="text-xs font-bold">{gettext("Priority queue")}</h3>
      <span class="text-[9px] font-semibold text-primary">{gettext("View all")}</span>
    </div>
    <div class="mt-2 rounded-xl border border-base-content/10 bg-base-100 shadow-sm">
      <.mobile_preview_row
        icon="icon-[tabler--mail-exclamation]"
        title="Acme Studio"
        detail={gettext("Proposal follow-up · 2h")}
        tone="warning"
      /><.mobile_preview_row
        icon="icon-[tabler--checkbox]"
        title="Launch checklist"
        detail={gettext("Due today · Assigned to you")}
        tone="primary"
      />
    </div>
    """
  end

  defp mobile_inbox_preview(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-bold">{gettext("Inbox")}</h2>
      <span class="btn btn-primary btn-xs gap-1">
        <.icon name="icon-[tabler--pencil]" class="size-3" />{gettext("Compose")}
      </span>
    </div>
    <div class="mt-3 flex h-8 items-center gap-2 rounded-lg border border-base-content/12 bg-base-200/45 px-2.5 text-[10px] text-base-content/45">
      <.icon name="icon-[tabler--search]" class="size-3.5" />{gettext("Search conversations")}
    </div>
    <div class="mt-3 overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm">
      <.mobile_inbox_row
        initials="AS"
        sender="Ava Simmons"
        subject={gettext("Re: onboarding timeline")}
        preview={gettext("Could we move our kickoff to Thursday?")}
        time="10:42"
        unread
      /><.mobile_inbox_row
        initials="MS"
        sender="Milo Scott"
        subject={gettext("A quick pricing question")}
        preview={gettext("One question about the Growth plan.")}
        time="09:18"
      /><.mobile_inbox_row
        initials="LD"
        sender="Lumen Design"
        subject={gettext("New project enquiry")}
        preview={gettext("Looking for a partner for our launch.")}
        time={gettext("Yesterday")}
      />
    </div>
    """
  end

  attr(:initials, :string, required: true)
  attr(:sender, :string, required: true)
  attr(:subject, :string, required: true)
  attr(:preview, :string, required: true)
  attr(:time, :string, required: true)
  attr(:unread, :boolean, default: false)

  defp mobile_inbox_row(assigns) do
    ~H"""
    <div class="flex items-start gap-3 border-b border-base-content/8 px-3 py-3 last:border-b-0">
      <span class={[
        "flex size-9 shrink-0 items-center justify-center rounded-full text-[10px] font-bold",
        @unread && "bg-primary/12 text-primary",
        !@unread && "bg-base-200 text-base-content/60"
      ]}>
        {@initials}
      </span>
      <div class="min-w-0 flex-1">
        <div class="flex items-baseline justify-between gap-2">
          <p class={[
            "truncate text-[11px]",
            @unread && "font-semibold",
            !@unread && "font-medium text-base-content/75"
          ]}>
            {@sender}
          </p>
          <span class="shrink-0 text-[8px] text-base-content/40">{@time}</span>
        </div>
        <p class={[
          "mt-0.5 truncate text-[10px]",
          @unread && "font-semibold",
          !@unread && "text-base-content/70"
        ]}>
          {@subject}
        </p>
        <p class="mt-0.5 truncate text-[9px] text-base-content/45">{@preview}</p>
      </div>
    </div>
    """
  end

  defp mobile_contacts_preview(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-bold">{gettext("Contacts")}</h2>
      <span class="btn btn-primary btn-xs btn-square">
        <.icon name="icon-[tabler--plus]" class="size-3.5" />
      </span>
    </div>
    <div class="mt-3 flex h-8 items-center gap-2 rounded-lg border border-base-content/12 bg-base-200/45 px-2.5 text-[10px] text-base-content/45">
      <.icon name="icon-[tabler--search]" class="size-3.5" />{gettext("Search contacts")}
    </div>
    <div class="mt-3 space-y-2">
      <.mobile_person_card initials="AS" name="Ava Simmons" detail="Acme Studio · Customer" /><.mobile_person_card
        initials="MS"
        name="Milo Scott"
        detail="Northstar · Lead"
      /><.mobile_person_card initials="LD" name="Lumen Design" detail="Prospect · New enquiry" />
    </div>
    """
  end

  defp mobile_companies_preview(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-bold">{gettext("Companies")}</h2>
      <span class="btn btn-primary btn-xs btn-square">
        <.icon name="icon-[tabler--plus]" class="size-3.5" />
      </span>
    </div>
    <div class="mt-3 grid grid-cols-2 gap-2">
      <.mobile_company_card
        name="Acme Studio"
        detail={gettext("4 contacts · Active")}
        icon="icon-[tabler--palette]"
      /><.mobile_company_card
        name="Northstar"
        detail={gettext("2 contacts · Lead")}
        icon="icon-[tabler--star]"
      /><.mobile_company_card
        name="Lumen Design"
        detail={gettext("1 contact · New")}
        icon="icon-[tabler--bulb]"
      /><.mobile_company_card
        name="Riviera Labs"
        detail={gettext("3 contacts · Active")}
        icon="icon-[tabler--flask]"
      />
    </div>
    """
  end

  defp mobile_deals_preview(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-bold">{gettext("Deals")}</h2>
      <span class="btn btn-primary btn-xs gap-1">
        <.icon name="icon-[tabler--plus]" class="size-3" />{gettext("New deal")}
      </span>
    </div>
    <div class="mt-3 space-y-2">
      <div class="overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm">
        <div class="flex items-center justify-between border-b border-base-content/10 bg-primary/5 px-3 py-2.5">
          <span class="flex items-center gap-2 text-[11px] font-semibold">
            <span class="size-2 rounded-full bg-primary" />{gettext("Proposal")}
          </span>
          <span class="flex items-center gap-2">
            <span class="badge badge-primary badge-sm text-[8px]">1</span>
            <.icon
              name="icon-[tabler--chevron-up]"
              class="size-3.5 text-base-content/40"
            />
          </span>
        </div>
        <div class="bg-base-200/30 p-2">
          <.mobile_deal_card
            name="Acme expansion"
            amount="€8,400"
            stage={gettext("Due Friday")}
            tone="primary"
          />
        </div>
      </div>
      <div class="flex items-center justify-between rounded-xl border border-base-content/10 bg-base-100 px-3 py-3 shadow-sm">
        <span class="flex items-center gap-2 text-[11px] font-semibold">
          <span class="size-2 rounded-full bg-success" />{gettext("Qualified")}
        </span>
        <span class="flex items-center gap-2">
          <span class="badge badge-sm text-[8px]">2</span>
          <.icon
            name="icon-[tabler--chevron-down]"
            class="size-3.5 text-base-content/40"
          />
        </span>
      </div>
      <div class="flex items-center justify-between rounded-xl border border-base-content/10 bg-base-100 px-3 py-3 shadow-sm">
        <span class="flex items-center gap-2 text-[11px] font-semibold">
          <span class="size-2 rounded-full bg-warning" />{gettext("New")}
        </span>
        <span class="flex items-center gap-2">
          <span class="badge badge-sm text-[8px]">3</span>
          <.icon
            name="icon-[tabler--chevron-down]"
            class="size-3.5 text-base-content/40"
          />
        </span>
      </div>
    </div>
    """
  end

  defp mobile_calendar_preview(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <div>
        <p class="text-[10px] text-base-content/45">{gettext("March 2026")}</p>
        <h2 class="text-lg font-bold">{gettext("Calendar")}</h2>
      </div>
      <span class="btn btn-primary btn-xs btn-square">
        <.icon name="icon-[tabler--plus]" class="size-3.5" />
      </span>
    </div>
    <div class="mt-3 grid grid-cols-5 gap-1 text-center">
      <%= for {day, date} <- [{"M", "10"}, {"T", "11"}, {"W", "12"}, {"T", "13"}, {"F", "14"}] do %>
        <div>
          <p class="text-[8px] text-base-content/45">{day}</p>
          <span class={[
            "mt-1 flex size-7 items-center justify-center rounded-full text-[10px] font-semibold",
            date == "12" && "bg-primary text-primary-content",
            date != "12" && "text-base-content/70"
          ]}>
            {date}
          </span>
        </div>
      <% end %>
    </div>
    <div class="mt-4 space-y-2">
      <.mobile_preview_row
        icon="icon-[tabler--video]"
        title={gettext("Acme kickoff")}
        detail={gettext("10:00 · 45 min")}
        tone="primary"
      /><.mobile_preview_row
        icon="icon-[tabler--phone]"
        title={gettext("Northstar check-in")}
        detail={gettext("13:30 · 30 min")}
        tone="primary"
      /><.mobile_preview_row
        icon="icon-[tabler--calendar-event]"
        title={gettext("Team planning")}
        detail={gettext("16:00 · 1 hour")}
        tone="warning"
      />
    </div>
    """
  end

  defp mobile_tasks_preview(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-bold">{gettext("Tasks")}</h2>
      <span class="btn btn-primary btn-xs gap-1">
        <.icon name="icon-[tabler--plus]" class="size-3" />{gettext("New task")}
      </span>
    </div>
    <div class="mt-3 overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm">
      <div class="grid grid-cols-[minmax(0,1fr)_5.25rem] border-b border-base-content/10 bg-base-200/35 px-3 py-2 text-[8px] font-semibold uppercase tracking-wide text-base-content/45">
        <span>{gettext("Task")}</span><span>{gettext("Status")}</span>
      </div>
      <div class="grid grid-cols-[minmax(0,1fr)_5.25rem] items-center border-b border-base-content/8 px-3 py-2.5">
        <div class="flex min-w-0 items-center gap-2">
          <span class="flex size-5 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary">
            <.icon name="icon-[tabler--chevron-down]" class="size-3" />
          </span>
          <span class="flex size-6 shrink-0 items-center justify-center rounded-lg border border-primary/30 bg-primary/10 text-primary">
            <.icon
              name="icon-[tabler--crown]"
              class="size-3"
            />
          </span>
          <div class="min-w-0">
            <p class="truncate text-[10px] font-semibold">{gettext("Customer onboarding")}</p>
            <p class="mt-0.5 text-[8px] text-base-content/45">{gettext("1/3 children complete")}</p>
          </div>
        </div>
        <span class="inline-flex whitespace-nowrap items-center gap-1 rounded-md border border-[#8b5cf6]/35 bg-[#8b5cf6]/12 px-1.5 py-1 text-center text-[8px] font-medium text-[#8b5cf6]">
          <.icon name="icon-[tabler--circle-half-2]" class="size-2.5" />{gettext("In progress")}
        </span>
      </div>
      <div class="ml-6 border-l border-base-content/12">
        <div class="grid grid-cols-[minmax(0,1fr)_5.25rem] items-center px-3 py-2.5">
          <div class="flex min-w-0 items-center gap-2">
            <span class="size-5 shrink-0" />
            <span class="flex size-6 shrink-0 items-center justify-center rounded-lg border border-warning/30 bg-warning/10 text-warning">
              <.icon name="icon-[tabler--menu-2]" class="size-3" />
            </span>
            <div class="min-w-0">
              <p class="truncate text-[10px] font-medium">{gettext("Confirm kickoff time")}</p>
              <p class="mt-0.5 text-[8px] text-base-content/45">
                {gettext("Ava Simmons · Due today")}
              </p>
            </div>
          </div>
          <span class="inline-flex whitespace-nowrap items-center gap-1 rounded-md border border-[#0ea5e9]/35 bg-[#0ea5e9]/12 px-1.5 py-1 text-[8px] font-medium text-[#0ea5e9]">
            <.icon name="icon-[tabler--circle]" class="size-2.5" />{gettext("Open")}
          </span>
        </div>
        <div class="grid grid-cols-[minmax(0,1fr)_5.25rem] items-center border-t border-base-content/8 px-3 py-2.5">
          <div class="flex min-w-0 items-center gap-2">
            <span class="size-5 shrink-0" />
            <span class="flex size-6 shrink-0 items-center justify-center rounded-lg border border-[#8b5cf6]/35 bg-[#8b5cf6]/12 text-[#8b5cf6]">
              <.icon name="icon-[tabler--menu-2]" class="size-3" />
            </span>
            <div class="min-w-0">
              <p class="truncate text-[10px] font-medium">{gettext("Prepare account")}</p>
              <p class="mt-0.5 text-[8px] text-base-content/45">{gettext("Working on the brief")}</p>
            </div>
          </div>
          <span class="inline-flex whitespace-nowrap items-center gap-1 rounded-md border border-[#8b5cf6]/35 bg-[#8b5cf6]/12 px-1.5 py-1 text-[8px] font-medium text-[#8b5cf6]">
            <.icon name="icon-[tabler--circle-half-2]" class="size-2.5" />{gettext("In progress")}
          </span>
        </div>
      </div>
      <div class="grid grid-cols-[minmax(0,1fr)_5.25rem] items-center border-t border-base-content/8 px-3 py-2.5">
        <div class="flex min-w-0 items-center gap-2">
          <span class="size-5 shrink-0" />
          <span class="flex size-6 shrink-0 items-center justify-center rounded-lg border border-warning/30 bg-warning/10 text-warning">
            <.icon name="icon-[tabler--menu-2]" class="size-3" />
          </span>
          <div class="min-w-0">
            <p class="truncate text-[10px] font-semibold">{gettext("Send Acme proposal")}</p>
            <p class="mt-0.5 text-[8px] text-base-content/45">
              {gettext("High priority · Due today")}
            </p>
          </div>
        </div>
        <span class="inline-flex whitespace-nowrap items-center gap-1 rounded-md border border-[#0ea5e9]/35 bg-[#0ea5e9]/12 px-1.5 py-1 text-[8px] font-medium text-[#0ea5e9]">
          <.icon name="icon-[tabler--circle]" class="size-2.5" />{gettext("Open")}
        </span>
      </div>
    </div>
    <div class="hidden mt-3 overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm">
      <div class="flex items-start gap-2 border-b border-base-content/8 px-3 py-3">
        <.icon name="icon-[tabler--chevron-down]" class="mt-1 size-3.5 shrink-0 text-base-content/45" />
        <span class="flex size-7 shrink-0 items-center justify-center rounded-lg border border-primary/30 bg-primary/10 text-primary">
          <.icon name="icon-[tabler--crown]" class="size-3.5" />
        </span>
        <div class="min-w-0 flex-1">
          <div class="flex items-center justify-between gap-2">
            <p class="truncate text-[11px] font-semibold">{gettext("Customer onboarding")}</p>
            <span class="rounded-md border border-base-content/10 bg-base-200/60 px-1.5 py-0.5 text-[8px] font-medium text-base-content/55">
              1/3
            </span>
          </div>
          <p class="mt-1 text-[9px] text-base-content/50">{gettext("Epic · Status from children")}</p>
        </div>
      </div>
      <div class="ml-5 border-l border-base-content/12 py-1.5">
        <div class="relative flex items-center gap-2 px-3 py-2.5">
          <span class="absolute -left-1 top-1/2 size-2 -translate-y-1/2 rounded-full bg-base-100 ring-1 ring-base-content/20" />
          <span class="flex size-5 shrink-0 items-center justify-center rounded-full border border-base-content/25">
            <.icon name="icon-[tabler--check]" class="size-3 text-base-content/25" />
          </span>
          <div class="min-w-0">
            <p class="truncate text-[10px] font-medium">{gettext("Confirm kickoff time")}</p>
            <p class="mt-0.5 text-[8px] text-base-content/45">{gettext("Ava Simmons · Due today")}</p>
          </div>
        </div>
        <div class="relative flex items-center gap-2 px-3 py-2.5">
          <span class="absolute -left-1 top-1/2 size-2 -translate-y-1/2 rounded-full bg-base-100 ring-1 ring-base-content/20" />
          <span class="flex size-5 shrink-0 items-center justify-center rounded-full border border-primary bg-primary text-primary-content">
            <.icon name="icon-[tabler--check]" class="size-3" />
          </span>
          <div class="min-w-0">
            <p class="truncate text-[10px] font-medium text-base-content/45 line-through">
              {gettext("Prepare account notes")}
            </p>
            <p class="mt-0.5 text-[8px] text-base-content/45">{gettext("Completed")}</p>
          </div>
        </div>
      </div>
      <div class="flex items-center gap-2 border-t border-base-content/8 px-3 py-3">
        <span class="size-3.5 shrink-0" />
        <span class="flex size-7 shrink-0 items-center justify-center rounded-lg border border-warning/30 bg-warning/10 text-warning">
          <.icon name="icon-[tabler--menu-2]" class="size-3.5" />
        </span>
        <div class="min-w-0 flex-1">
          <p class="truncate text-[11px] font-semibold">{gettext("Send Acme proposal")}</p>
          <p class="mt-1 text-[9px] text-base-content/50">{gettext("High priority · Due today")}</p>
        </div>
      </div>
    </div>
    """
  end

  attr(:value, :string, required: true)
  attr(:label, :string, required: true)
  attr(:tone, :string, required: true)

  defp mobile_preview_metric(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-content/8 bg-base-100 p-2.5 shadow-sm">
      <span class={["block size-1.5 rounded-full", metric_tone(@tone)]} />
      <p class="mt-2 text-base font-bold leading-none">{@value}</p>
      <p class="mt-1 text-[9px] text-base-content/50">{@label}</p>
    </div>
    """
  end

  attr(:icon, :string, required: true)
  attr(:title, :string, required: true)
  attr(:detail, :string, required: true)
  attr(:tone, :string, required: true)
  attr(:unread, :boolean, default: false)

  defp mobile_preview_row(assigns) do
    ~H"""
    <div class="flex items-center gap-2.5 border-b border-base-content/8 px-3 py-2.5 last:border-b-0">
      <span class={[
        "flex size-8 shrink-0 items-center justify-center rounded-xl",
        mobile_tone_surface(@tone)
      ]}>
        <.icon name={@icon} class="size-4" />
      </span>
      <div class="min-w-0 flex-1">
        <p class={["truncate text-[11px]", @unread && "font-bold", !@unread && "font-semibold"]}>
          {@title}
        </p>
        <p class="mt-0.5 truncate text-[9px] text-base-content/50">{@detail}</p>
      </div>
      <.icon name="icon-[tabler--chevron-right]" class="size-3.5 text-base-content/30" />
    </div>
    """
  end

  attr(:initials, :string, required: true)
  attr(:name, :string, required: true)
  attr(:detail, :string, required: true)

  defp mobile_person_card(assigns) do
    ~H"""
    <div class="flex items-center gap-2.5 rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm">
      <span class="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary/12 text-[10px] font-bold text-primary">
        {@initials}
      </span>
      <div class="min-w-0">
        <p class="truncate text-[11px] font-semibold">{@name}</p>
        <p class="mt-0.5 truncate text-[9px] text-base-content/50">{@detail}</p>
      </div>
    </div>
    """
  end

  attr(:name, :string, required: true)
  attr(:detail, :string, required: true)
  attr(:icon, :string, required: true)

  defp mobile_company_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm">
      <span class="flex size-8 items-center justify-center rounded-lg bg-primary/10 text-primary">
        <.icon name={@icon} class="size-4" />
      </span>
      <p class="mt-3 truncate text-[10px] font-semibold">{@name}</p>
      <p class="mt-1 truncate text-[8px] text-base-content/50">{@detail}</p>
    </div>
    """
  end

  attr(:name, :string, required: true)
  attr(:amount, :string, required: true)
  attr(:stage, :string, required: true)
  attr(:tone, :string, required: true)

  defp mobile_deal_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm">
      <div class="flex items-start justify-between gap-2">
        <div class="min-w-0">
          <p class="truncate text-[11px] font-semibold">{@name}</p>
          <p class="mt-1 text-sm font-bold">{@amount}</p>
        </div>
        <span class={["rounded-full px-2 py-1 text-[8px] font-semibold", mobile_tone_surface(@tone)]}>
          {@stage}
        </span>
      </div>
      <div class="mt-3 h-1.5 rounded-full bg-base-200">
        <div class={[
          "h-1.5 rounded-full",
          metric_tone(@tone),
          @tone == "primary" && "w-3/4",
          @tone == "success" && "w-1/2",
          @tone == "warning" && "w-1/4"
        ]} />
      </div>
    </div>
    """
  end

  defp home_preview(assigns) do
    ~H"""
    <.preview_heading
      eyebrow={gettext("Tuesday brief")}
      title={gettext("Everything that needs you")}
      icon="icon-[tabler--sparkles]"
    />
    <div class="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
      <.preview_metric label={gettext("Needs reply")} value="8" tone="warning" />
      <.preview_metric label={gettext("At risk")} value="€12.4k" tone="error" />
      <.preview_metric label={gettext("Tasks due")} value="5" tone="primary" />
      <.preview_metric label={gettext("Closing soon")} value="3" tone="success" />
    </div>
    <div class="mt-4 grid gap-3 lg:grid-cols-[1.1fr_.9fr]">
      <section class="rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm">
        <h3 class="text-xs font-bold">{gettext("Priority queue")}</h3>
        <p class="mt-0.5 text-[10px] text-base-content/50">
          {gettext("Leads waiting on your reply")}
        </p>
        <div class="mt-2 divide-y divide-base-content/8">
          <.preview_row
            initials="AC"
            name="Acme Studio"
            detail={gettext("Proposal follow-up")}
            age="2h"
          />
          <.preview_row
            initials="RL"
            name="Riviera Labs"
            detail={gettext("Pricing question")}
            age="4h"
          />
          <.preview_row initials="PN" name="Pine & North" detail={gettext("New enquiry")} age="5h" />
        </div>
      </section>
      <section class="rounded-xl border border-primary/18 bg-primary/6 p-3">
        <div class="flex items-center justify-between">
          <h3 class="text-xs font-bold">{gettext("AI next step")}</h3>
          <.icon name="icon-[tabler--sparkles]" class="size-4 text-primary" />
        </div>
        <p class="mt-3 text-xs font-medium leading-5">
          {gettext("Draft a warm follow-up for Acme Studio before their proposal goes cold.")}
        </p>
        <span class="btn btn-primary btn-xs mt-3 w-full">{gettext("Review draft")}</span>
      </section>
    </div>
    <section class="mt-3 rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm">
      <div class="flex items-center justify-between">
        <div>
          <h3 class="text-xs font-bold">{gettext("Pipeline")}</h3>
          <p class="mt-0.5 text-[10px] text-base-content/50">
            {gettext("€36.8k active opportunities")}
          </p>
        </div>
        <.icon name="icon-[tabler--chart-arrows]" class="size-4 text-primary" />
      </div>
      <div class="mt-3 grid grid-cols-4 gap-2">
        <.pipeline_column label={gettext("New")} value="€9k" count="3" /><.pipeline_column
          label={gettext("Qualified")}
          value="€11k"
          count="4"
        /><.pipeline_column label={gettext("Proposal")} value="€12k" count="2" /><.pipeline_column
          label={gettext("Close")}
          value="€5k"
          count="1"
        />
      </div>
    </section>
    """
  end

  defp inbox_preview(assigns) do
    ~H"""
    <div class="flex h-full gap-2">
      <aside class="hidden w-24 shrink-0 self-start rounded-xl bg-base-100 py-2">
        <span class="mx-2 flex items-center justify-center gap-1 rounded-lg border border-primary/30 bg-primary/8 px-2 py-2 text-[8px] font-semibold text-primary">
          <.icon name="icon-[tabler--send]" class="size-3" />{gettext("Compose")}
        </span>
        <div class="mt-3 space-y-0.5 px-1.5">
          <.inbox_view label={gettext("Inbox")} icon="icon-[tabler--inbox]" count="8" active /><.inbox_view
            label={gettext("Favorites")}
            icon="icon-[tabler--star]"
            count="2"
          /><.inbox_view label={gettext("Sent")} icon="icon-[tabler--send]" count="" /><.inbox_view
            label={gettext("Scheduled")}
            icon="icon-[tabler--clock]"
            count="3"
          /><.inbox_view label={gettext("Archived")} icon="icon-[tabler--archive]" count="" />
        </div>
      </aside>
      <section class="grid h-full min-w-0 flex-1 grid-cols-[7.25rem_minmax(0,1fr)] overflow-hidden bg-base-100 sm:grid-cols-[10.75rem_minmax(0,1fr)]">
        <div class="min-w-0 border-r border-base-content/10">
          <div class="flex items-center gap-1.5 border-b border-base-content/10 px-2 py-2.5">
            <div class="relative min-w-0 flex-1">
              <.icon
                name="icon-[tabler--search]"
                class="absolute left-2 top-1/2 size-3 -translate-y-1/2 text-base-content/40"
              />
              <div class="h-7 rounded-md border border-base-content/20 pl-7 text-[9px] leading-7 text-base-content/40">
                {gettext("Search subjects...")}
              </div>
            </div>
            <span class="btn btn-xs btn-square border-primary/25 bg-primary/10 text-primary">
              <.icon name="icon-[tabler--refresh]" class="size-3" />
            </span>
          </div>
          <div class="flex items-center gap-3 border-b border-base-content/10 px-3 py-2">
            <span class="text-[9px] font-bold text-primary">{gettext("Inbox")}</span><span class="text-[9px] text-base-content/45">{gettext("All")}</span><span class="text-[9px] text-base-content/45">{gettext("Unread")}</span>
          </div>
          <div class="divide-y divide-base-content/8">
            <.inbox_list_row
              sender="Ava Simmons"
              subject={gettext("Re: onboarding timeline")}
              preview={gettext("Could we move our kickoff to Thursday afternoon?")}
              time="10:42"
              unread
            /><.inbox_list_row
              sender="Milo Scott"
              subject={gettext("A quick pricing question")}
              preview={gettext("Thanks — I have one question about the Growth plan.")}
              time="09:18"
            /><.inbox_list_row
              sender="Lumen Design"
              subject={gettext("New project enquiry")}
              preview={gettext("We are looking for a partner for our upcoming launch.")}
              time={gettext("Yesterday")}
            /><.inbox_list_row
              sender="Northstar"
              subject={gettext("Meeting notes")}
              preview={gettext("Sharing the action items from our call.")}
              time={gettext("Mon")}
            />
          </div>
        </div>
        <div class="min-w-0 bg-base-100 p-2.5 sm:p-3">
          <div class="rounded-lg border border-base-content/10 bg-base-100 p-2.5">
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <h3 class="truncate text-[11px] font-semibold leading-tight">
                  {gettext("Re: onboarding timeline")}
                </h3>
                <div class="mt-1.5 flex items-center gap-1.5">
                  <span class="rounded-full bg-primary/10 px-1.5 py-0.5 text-[8px] font-medium text-primary">
                    {gettext("Customer")}
                  </span>
                  <span class="text-[8px] text-base-content/45">{gettext("Unresolved")}</span>
                </div>
              </div>
              <span class="btn btn-xs btn-primary h-6 min-h-6 gap-1 px-2 text-[8px]">
                <.icon name="icon-[tabler--corner-down-left]" class="size-3" />
                {gettext("Reply")}
              </span>
            </div>
          </div>

          <article class="mt-2.5 overflow-hidden rounded-lg border border-base-content/10 bg-base-100 shadow-sm shadow-base-content/5">
            <div class="flex items-start gap-2 border-b border-base-content/10 px-3 py-2.5">
              <span class="flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/15 text-[9px] font-bold text-primary">
                AS
              </span>
              <div class="min-w-0 flex-1">
                <div class="flex items-baseline justify-between gap-2">
                  <span class="truncate text-[10px] font-semibold">Ava Simmons</span>
                  <span class="shrink-0 text-[8px] font-medium text-base-content/60">10:42</span>
                </div>
                <p class="mt-0.5 truncate text-[8px] text-base-content/50">
                  {gettext("To: Konevo team")}
                </p>
              </div>
            </div>
            <div class="bg-base-200/25 px-3 py-3">
              <div class="rounded-md border border-base-content/10 bg-base-100 px-3 py-2.5 text-[9px] leading-[1.55] text-base-content/80 shadow-inner shadow-base-content/5">
                <p>{gettext("Hi team,")}</p>
                <p class="mt-2">
                  {gettext("Excited to get started. Could we move our kickoff to Thursday afternoon?")}
                </p>
                <p class="mt-2">{gettext("Thanks, Ava")}</p>
              </div>
            </div>
          </article>

          <div class="mt-2.5 flex items-center gap-1.5 rounded-lg border border-primary/18 bg-primary/6 px-2.5 py-2 text-[8px] text-base-content/70">
            <.icon name="icon-[tabler--sparkles]" class="size-3 shrink-0 text-primary" />
            <span class="font-semibold text-primary">{gettext("AI suggests")}</span>
            <span class="truncate">
              {gettext("Offer Thursday at 2 PM and create a kickoff task.")}
            </span>
          </div>
        </div>
      </section>
    </div>
    <div class="hidden">
      <.preview_heading
        eyebrow={gettext("Shared inbox")}
        title={gettext("Conversations, in context")}
        icon="icon-[tabler--mail-ai]"
      />
      <div class="mt-4 grid h-[22rem] grid-cols-[.85fr_1.15fr] overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm">
        <div class="border-r border-base-content/10 p-2">
          <div class="rounded-md bg-base-200/70 px-2 py-1.5 text-[9px] text-base-content/45">
            <.icon name="icon-[tabler--search]" class="mr-1 inline size-3" />{gettext(
              "Search conversations"
            )}
          </div>
          <div class="mt-2 space-y-1">
            <.inbox_item
              initials="AS"
              name="Ava Simmons"
              subject={gettext("Re: onboarding timeline")}
              selected
            /><.inbox_item
              initials="MS"
              name="Milo Scott"
              subject={gettext("A quick pricing question")}
            /><.inbox_item initials="LD" name="Lumen Design" subject={gettext("New project enquiry")} />
          </div>
        </div>
        <div class="min-w-0 p-3">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-[11px] font-bold">Ava Simmons</p>
              <p class="text-[9px] text-base-content/45">ava@northstar.co</p>
            </div>
            <span class="badge badge-primary badge-sm text-[9px]">{gettext("Customer")}</span>
          </div>
          <div class="mt-4 border-y border-base-content/8 py-3 text-[10px] leading-5 text-base-content/65">
            {gettext(
              "Hi team — excited to get started. Could we move our kickoff to next Thursday afternoon?"
            )}
          </div>
          <div class="mt-3 rounded-lg bg-primary/6 p-2.5">
            <div class="flex items-center gap-1.5 text-[10px] font-bold text-primary">
              <.icon name="icon-[tabler--sparkles]" class="size-3" />{gettext("AI suggests")}
            </div>
            <p class="mt-1 text-[10px] leading-4">
              {gettext("Offer Thursday at 2 PM and create a kickoff task.")}
            </p>
          </div>
          <div class="mt-3 flex gap-2">
            <span class="btn btn-primary btn-xs">{gettext("Reply")}</span><span class="btn btn-ghost btn-xs">{gettext("Assign")}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp contacts_preview(assigns) do
    ~H"""
    <div class="flex h-full min-h-0 flex-col overflow-hidden">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-bold">{gettext("Contacts")}</h2>
        <span class="btn btn-primary btn-xs gap-1">
          <.icon name="icon-[tabler--plus]" class="size-3" />{gettext("New contact")}
        </span>
      </div>
      <div class="mt-3 flex flex-wrap items-center gap-2">
        <div class="relative w-40">
          <.icon
            name="icon-[tabler--search]"
            class="absolute left-2 top-1/2 size-3 -translate-y-1/2 text-base-content/40"
          />
          <div class="h-7 rounded-md border border-base-content/20 bg-base-100 pl-7 text-[9px] leading-7 text-base-content/40">
            {gettext("Search contacts...")}
          </div>
        </div>
        <span class="btn btn-xs border-base-content/20 bg-base-200/60 text-[9px] text-base-content">
          <.icon name="icon-[tabler--archive]" class="size-3" />{gettext("Active")}
        </span>
        <span class="btn btn-xs border-base-content/20 bg-base-200/60 text-[9px] text-base-content">
          <.icon
            name="icon-[tabler--tag]"
            class="size-3"
          />{gettext("Category")}
        </span>
        <span class="ml-auto flex rounded-md border border-base-content/15 bg-base-100 p-0.5">
          <span class="rounded bg-neutral px-2 py-1 text-[8px] text-neutral-content">
            <.icon
              name="icon-[tabler--table]"
              class="size-3"
            />
          </span>
          <span class="px-2 py-1 text-[8px] text-base-content/45">
            <.icon
              name="icon-[tabler--layout-grid]"
              class="size-3"
            />
          </span>
        </span>
      </div>
      <section class="mt-2 min-h-0 flex-1 overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm">
        <table class="w-full table-fixed">
          <thead>
            <tr class="border-b border-base-content/10 bg-base-200/35 text-left text-[8px] font-bold uppercase tracking-wide text-base-content/45">
              <th class="px-3 py-1.5">{gettext("Name")}</th>
              <th class="px-3 py-1.5">{gettext("Email")}</th>
              <th class="px-3 py-1.5">{gettext("Company")}</th>
              <th class="px-3 py-1.5">{gettext("Category")}</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-content/8">
            <.contact_table_row
              initials="AS"
              name="Ava Simmons"
              email="ava@northstar.co"
              company="Northstar"
              category={gettext("Customer")}
            /><.contact_table_row
              initials="MB"
              name="Marek Blazek"
              email="marek@studio.sk"
              company="Studio One"
              category={gettext("Lead")}
            /><.contact_table_row
              initials="JD"
              name="Jules Dubois"
              email="jules@riviere.fr"
              company="Riviera Labs"
              category={gettext("Customer")}
            /><.contact_table_row
              initials="SN"
              name="Sam Novak"
              email="sam@pinenorth.com"
              company="Pine & North"
              category={gettext("Lead")}
            />
          </tbody>
        </table>
      </section>
    </div>
    <div class="hidden">
      <.preview_heading
        eyebrow={gettext("Relationship intelligence")}
        title={gettext("Every customer, known")}
        icon="icon-[tabler--users]"
      />
      <div class="mt-4 rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm">
        <div class="flex items-center justify-between">
          <div class="rounded-md bg-base-200/70 px-2 py-1.5 text-[9px] text-base-content/45">
            <.icon name="icon-[tabler--search]" class="mr-1 inline size-3" />{gettext(
              "Search contacts"
            )}
          </div>
          <span class="btn btn-primary btn-xs">{gettext("New contact")}</span>
        </div>
        <div class="mt-3 overflow-hidden rounded-lg border border-base-content/8">
          <div class="grid grid-cols-[1.25fr_.8fr_.65fr] bg-base-200/45 px-3 py-2 text-[8px] font-bold uppercase tracking-wide text-base-content/45">
            <span>{gettext("Contact")}</span><span>{gettext("Company")}</span><span>{gettext("Last touch")}</span>
          </div>
          <.contact_item
            initials="AS"
            name="Ava Simmons"
            email="ava@northstar.co"
            company="Northstar"
            touch={gettext("Today")}
          /><.contact_item
            initials="MB"
            name="Marek Blažek"
            email="marek@studio.sk"
            company="Studio One"
            touch={gettext("Yesterday")}
          /><.contact_item
            initials="JD"
            name="Jules Dubois"
            email="jules@riviere.fr"
            company="Riviera Labs"
            touch={gettext("3 days ago")}
          /><.contact_item
            initials="SN"
            name="Sam Novak"
            email="sam@pinenorth.com"
            company="Pine & North"
            touch={gettext("1 week ago")}
          />
        </div>
      </div>
      <div class="mt-3 grid grid-cols-3 gap-2">
        <.preview_metric label={gettext("New this week")} value="24" tone="primary" /><.preview_metric
          label={gettext("With open deals")}
          value="18"
          tone="success"
        /><.preview_metric label={gettext("Needs follow-up")} value="6" tone="warning" />
      </div>
    </div>
    """
  end

  defp companies_preview(assigns) do
    ~H"""
    <div class="flex h-full min-h-0 flex-col overflow-hidden">
      <div class="flex items-center justify-between gap-3">
        <h2 class="text-lg font-bold">{gettext("Companies")}</h2>
        <span class="btn btn-primary btn-xs gap-1">
          <.icon name="icon-[tabler--plus]" class="size-3" />{gettext("New Company")}
        </span>
      </div>
      <div class="mt-3 flex flex-wrap items-center gap-2">
        <div class="relative w-40">
          <.icon
            name="icon-[tabler--search]"
            class="absolute left-2 top-1/2 size-3 -translate-y-1/2 text-base-content/40"
          />
          <div class="h-7 rounded-md border border-base-content/20 bg-base-100 pl-7 pr-2 text-[9px] leading-7 text-base-content/40">
            {gettext("Search by name, website...")}
          </div>
        </div>
        <span class="btn btn-xs border-base-content/20 bg-base-200/60 text-[9px] text-base-content">
          <.icon name="icon-[tabler--archive]" class="size-3" />{gettext("Active")}
        </span>
        <span class="btn btn-xs border-base-content/20 bg-base-200/60 text-[9px] text-base-content">
          <.icon name="icon-[tabler--building]" class="size-3" />{gettext("Industry")}
        </span>
        <span class="ml-auto flex rounded-md border border-base-content/15 bg-base-100 p-0.5">
          <span class="rounded bg-neutral px-2 py-1 text-[8px] text-neutral-content">
            <.icon name="icon-[tabler--table]" class="size-3" />
          </span>
          <span class="px-2 py-1 text-[8px] text-base-content/45">
            <.icon
              name="icon-[tabler--layout-grid]"
              class="size-3"
            />
          </span>
        </span>
      </div>
      <section class="mt-2 min-h-0 flex-1 overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm">
        <div class="grid grid-cols-[1.2fr_.7fr_.65fr_.45fr] border-b border-base-content/10 bg-base-200/35 px-3 py-1.5 text-[8px] font-bold uppercase tracking-wide text-base-content/45">
          <span>{gettext("Company")}</span><span>{gettext("Industry")}</span><span>{gettext("Contacts")}</span><span>{gettext("Created")}</span>
        </div>
        <.company_item
          name="Northstar"
          website="northstar.co"
          industry={gettext("Technology")}
          contacts="12"
          created={gettext("Today")}
        /><.company_item
          name="Acme Studio"
          website="acmestudio.com"
          industry={gettext("Design")}
          contacts="8"
          created={gettext("Yesterday")}
        /><.company_item
          name="Riviera Labs"
          website="rivieralabs.io"
          industry={gettext("SaaS")}
          contacts="5"
          created={gettext("Oct 9")}
        /><.company_item
          name="Pine & North"
          website="pinenorth.com"
          industry={gettext("Consulting")}
          contacts="3"
          created={gettext("Oct 7")}
        />
      </section>
    </div>
    """
  end

  defp deals_preview(assigns) do
    ~H"""
    <div class="flex h-full flex-col">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-bold">{gettext("Deals")}</h2>
        <span class="btn btn-primary btn-xs gap-1">
          <.icon name="icon-[tabler--plus]" class="size-3" />{gettext("Add deal")}
        </span>
      </div>
      <div class="mt-3 flex flex-wrap items-center gap-2">
        <div class="relative w-36">
          <.icon
            name="icon-[tabler--search]"
            class="absolute left-2 top-1/2 size-3 -translate-y-1/2 text-base-content/40"
          />
          <div class="h-7 rounded-md border border-base-content/20 pl-7 text-[9px] leading-7 text-base-content/40">
            {gettext("Search deals...")}
          </div>
        </div>
        <span class="btn btn-xs border-base-content/20 bg-base-200/60 text-[9px] text-base-content">
          <.icon name="icon-[tabler--adjustments-horizontal]" class="size-3" />{gettext("Filters")}
        </span>
        <span class="btn btn-xs border-base-content/20 bg-base-200/60 text-[9px] text-base-content">
          <.icon
            name="icon-[tabler--calendar]"
            class="size-3"
          />{gettext("Close date")}
        </span>
        <span class="ml-auto text-[9px] text-base-content/45">
          {gettext("5 active deals · €40.0k")}
        </span>
      </div>
      <div class="mt-3 grid min-h-0 flex-1 grid-cols-3 gap-2 overflow-hidden">
        <.deal_column
          title={gettext("Qualified")}
          amount="€18.5k"
          cards={[{"Northstar", "€8.5k"}, {"Milo Studio", "€10k"}]}
          color="#0ea5e9"
        /><.deal_column
          title={gettext("Proposal")}
          amount="€12.4k"
          cards={[{"Acme Studio", "€7.4k"}, {"Riviera Labs", "€5k"}]}
          color="#f59e0b"
        /><.deal_column
          title={gettext("Closing")}
          amount="€9.1k"
          cards={[{"Pine & North", "€9.1k"}]}
          color="#10b981"
        />
      </div>
    </div>
    <div class="hidden">
      <.preview_heading
        eyebrow={gettext("Revenue pipeline")}
        title={gettext("Momentum you can see")}
        icon="icon-[tabler--briefcase]"
      />
      <div class="mt-4 grid grid-cols-3 gap-2">
        <.deal_column
          title={gettext("Qualified")}
          amount="€18.5k"
          cards={[{"Northstar", "€8.5k"}, {"Milo Studio", "€10k"}]}
        /><.deal_column
          title={gettext("Proposal")}
          amount="€12.4k"
          cards={[{"Acme Studio", "€7.4k"}, {"Riviera Labs", "€5k"}]}
        /><.deal_column
          title={gettext("Closing")}
          amount="€9.1k"
          cards={[{"Pine & North", "€9.1k"}]}
        />
      </div>
      <section class="mt-3 rounded-xl border border-primary/18 bg-primary/6 p-3">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-[10px] font-bold">{gettext("Forecast")}</p>
            <p class="mt-1 text-[9px] text-base-content/50">
              {gettext("Based on deal activity this month")}
            </p>
          </div>
          <p class="text-lg font-bold text-primary">€40.0k</p>
        </div>
        <div class="mt-3 h-2 overflow-hidden rounded-full bg-base-100">
          <div class="h-full w-[72%] rounded-full bg-primary" />
        </div>
      </section>
    </div>
    """
  end

  defp calendar_preview(assigns) do
    ~H"""
    <div class="flex h-full flex-col">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-bold">{gettext("Calendar")}</h2>
        <span class="btn btn-primary btn-xs gap-1">
          <.icon name="icon-[tabler--plus]" class="size-3" />{gettext("New task")}
        </span>
      </div>
      <div class="mt-3 grid grid-cols-4 gap-2">
        <.calendar_metric
          icon="icon-[tabler--checkbox]"
          label={gettext("Tasks due")}
          value="12"
          tone="task"
        /><.calendar_metric
          icon="icon-[tabler--users]"
          label={gettext("Contacts in view")}
          value="6"
          tone="contact"
        /><.calendar_metric
          icon="icon-[tabler--building]"
          label={gettext("Companies in view")}
          value="4"
          tone="company"
        /><.calendar_metric
          icon="icon-[tabler--alert-circle]"
          label={gettext("Overdue in view")}
          value="2"
          tone="risk"
        />
      </div>
      <section class="mt-3 flex min-h-0 flex-1 flex-col overflow-hidden rounded-lg border border-base-content/10 bg-base-100 shadow-sm">
        <div class="flex flex-wrap items-center justify-between gap-2 border-b border-base-content/10 p-2.5">
          <div class="flex items-center gap-2">
            <span class="flex size-7 items-center justify-center rounded-md bg-primary/10 text-primary">
              <.icon name="icon-[tabler--calendar-week]" class="size-3.5" />
            </span>
            <div>
              <p class="text-[10px] font-semibold">{gettext("Planner")}</p>
              <p class="text-[8px] text-base-content/45">{gettext("18 events visible")}</p>
            </div>
          </div>
          <div class="join">
            <span class="btn btn-xs join-item border-base-content/15 bg-base-200/60 text-base-content">
              <.icon name="icon-[tabler--chevron-left]" class="size-3" />
            </span>
            <span class="btn btn-xs join-item border-base-content/15 bg-base-200/60 text-[9px] text-base-content">
              {gettext("Today")}
            </span>
            <span class="btn btn-xs join-item border-base-content/15 bg-base-200/60 text-base-content">
              <.icon
                name="icon-[tabler--chevron-right]"
                class="size-3"
              />
            </span>
          </div>
          <div class="join hidden sm:flex">
            <span class="btn btn-xs join-item border-0 bg-primary text-[8px] text-primary-content shadow-none">
              {gettext("Month")}
            </span>
            <span class="btn btn-xs join-item border-base-content/15 bg-base-200/60 text-[8px] text-base-content">
              {gettext("Week")}
            </span>
          </div>
        </div>
        <div class="flex gap-1 border-b border-base-content/10 px-2.5 py-1.5">
          <span class="rounded-md border border-primary/30 bg-primary/10 px-1.5 py-1 text-[8px] text-primary">
            <.icon name="icon-[tabler--checkbox]" class="mr-1 inline size-2.5" />{gettext("Tasks")}
          </span>
          <span class="rounded-md border border-base-content/15 px-1.5 py-1 text-[8px] text-base-content/60">
            <.icon
              name="icon-[tabler--users]"
              class="mr-1 inline size-2.5"
            />{gettext("Contacts")}
          </span>
          <span class="rounded-md border border-base-content/15 px-1.5 py-1 text-[8px] text-base-content/60">
            <.icon
              name="icon-[tabler--building]"
              class="mr-1 inline size-2.5"
            />{gettext("Companies")}
          </span>
        </div>
        <.calendar_month_grid />
        <div class="hidden min-h-0 flex-1 grid-cols-5 border-l border-t border-base-content/8">
          <.calendar_day
            day="MON"
            date="14"
            events={[{"Team standup", "primary"}, {"Acme kickoff", "success"}]}
          /><.calendar_day day="TUE" date="15" events={[{"Proposal review", "warning"}]} /><.calendar_day
            day="WED"
            date="16"
            events={[{"Ava · onboarding", "primary"}, {"Pipeline check", "error"}]}
          /><.calendar_day day="THU" date="17" events={[{"Northstar demo", "success"}]} /><.calendar_day
            day="FRI"
            date="18"
            events={[{"Weekly wrap", "warning"}]}
          />
        </div>
      </section>
    </div>
    <div class="hidden">
      <.preview_heading
        eyebrow={gettext("Team calendar")}
        title={gettext("A calmer week ahead")}
        icon="icon-[tabler--calendar-week]"
      />
      <div class="mt-4 rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span class="btn btn-xs btn-ghost">
              <.icon name="icon-[tabler--chevron-left]" class="size-3" />
            </span>
            <p class="text-xs font-bold">{gettext("October 14–18")}</p>
            <span class="btn btn-xs btn-ghost">
              <.icon name="icon-[tabler--chevron-right]" class="size-3" />
            </span>
          </div>
          <span class="btn btn-primary btn-xs">{gettext("New event")}</span>
        </div>
        <div class="mt-3 grid grid-cols-5 border-l border-t border-base-content/8">
          <.calendar_day
            day="MON"
            date="14"
            events={[{"Team standup", "primary"}, {"Acme kickoff", "success"}]}
          /><.calendar_day day="TUE" date="15" events={[{"Proposal review", "warning"}]} /><.calendar_day
            day="WED"
            date="16"
            events={[{"Ava · onboarding", "primary"}, {"Pipeline check", "error"}]}
          /><.calendar_day day="THU" date="17" events={[{"Northstar demo", "success"}]} /><.calendar_day
            day="FRI"
            date="18"
            events={[{"Weekly wrap", "warning"}]}
          />
        </div>
      </div>
    </div>
    """
  end

  defp tasks_preview(assigns) do
    ~H"""
    <div class="flex h-full flex-col">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-bold">{gettext("Tasks")}</h2>
        <span class="btn btn-primary btn-xs gap-1">
          <.icon name="icon-[tabler--plus]" class="size-3" />{gettext("New task")}
        </span>
      </div>
      <div class="mt-3 flex flex-wrap items-center gap-2">
        <div class="relative w-36">
          <.icon
            name="icon-[tabler--search]"
            class="absolute left-2 top-1/2 size-3 -translate-y-1/2 text-base-content/40"
          />
          <div class="h-7 rounded-md border border-base-content/20 pl-7 text-[9px] leading-7 text-base-content/40">
            {gettext("Search tasks...")}
          </div>
        </div>
        <span class="btn btn-xs border-base-content/20 bg-base-200/60 text-[9px] text-base-content">
          <.icon name="icon-[tabler--circle-check]" class="size-3" />{gettext("Status")}
        </span>
        <span class="btn btn-xs border-base-content/20 bg-base-200/60 text-[9px] text-base-content">
          <.icon
            name="icon-[tabler--flag]"
            class="size-3"
          />{gettext("Priority")}
        </span>
        <span class="btn btn-xs border-base-content/20 bg-base-200/60 text-[9px] text-base-content">
          <.icon
            name="icon-[tabler--calendar]"
            class="size-3"
          />{gettext("Due date")}
        </span>
        <span class="ml-auto text-[9px] text-base-content/45">{gettext("14 tasks")}</span>
      </div>
      <section class="mt-3 overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm">
        <div class="grid grid-cols-[1.45fr_.6fr_.7fr_.55fr] border-b border-base-content/10 bg-base-200/35 px-3 py-2 text-[8px] font-bold uppercase tracking-wide text-base-content/45">
          <span>{gettext("Task")}</span><span>{gettext("Status")}</span><span>{gettext("Priority")}</span><span>{gettext("Due")}</span>
        </div>
        <.task_tree_preview_row
          title={gettext("Send Acme Studio proposal")}
          status={gettext("In progress")}
          priority={gettext("Urgent")}
          due={gettext("Today")}
          type="epic"
          depth={0}
          children
        /><.task_tree_preview_row
          title={gettext("Confirm Ava's kickoff time")}
          status={gettext("Open")}
          priority={gettext("Normal")}
          due={gettext("Today")}
          type="task"
          depth={1}
        /><.task_tree_preview_row
          title={gettext("Prepare Northstar demo")}
          status={gettext("Open")}
          priority={gettext("High")}
          due={gettext("Tomorrow")}
          type="task"
          depth={1}
        /><.task_tree_preview_row
          title={gettext("Update Q4 pipeline notes")}
          status={gettext("Done")}
          priority={gettext("Low")}
          due={gettext("Friday")}
          type="task"
          depth={0}
        /><.task_tree_preview_row
          title={gettext("Follow up with Riviera Labs")}
          status={gettext("Open")}
          priority={gettext("High")}
          due={gettext("Oct 20")}
          type="task"
          depth={0}
        />
      </section>
    </div>
    <div class="hidden">
      <.preview_heading
        eyebrow={gettext("Focused execution")}
        title={gettext("Work that moves things forward")}
        icon="icon-[tabler--checkbox]"
      />
      <div class="mt-4 grid gap-3 sm:grid-cols-[1.2fr_.8fr]">
        <section class="rounded-xl border border-base-content/10 bg-base-100 p-3 shadow-sm">
          <div class="flex items-center justify-between">
            <h3 class="text-xs font-bold">{gettext("My tasks")}</h3>
            <span class="text-[9px] text-base-content/45">{gettext("5 due today")}</span>
          </div>
          <div class="mt-2 divide-y divide-base-content/8">
            <.task_item
              title={gettext("Send Acme Studio proposal")}
              meta={gettext("Due in 1h · Deal")}
              tone="error"
            /><.task_item
              title={gettext("Confirm Ava's kickoff time")}
              meta={gettext("Due today · Inbox")}
              tone="primary"
            /><.task_item
              title={gettext("Prepare Northstar demo")}
              meta={gettext("Tomorrow · Deal")}
              tone="warning"
            /><.task_item
              title={gettext("Update Q4 pipeline notes")}
              meta={gettext("Friday · Admin")}
              tone="success"
            />
          </div>
        </section>
        <section class="rounded-xl border border-primary/18 bg-primary/6 p-3">
          <p class="text-[10px] font-bold text-primary">{gettext("Your focus")}</p>
          <p class="mt-2 text-lg font-bold">{gettext("2 hours")}</p>
          <p class="mt-1 text-[10px] leading-4 text-base-content/55">
            {gettext("Protected for the work that needs your attention most.")}
          </p>
          <div class="mt-4 space-y-2">
            <div class="h-2 w-full rounded-full bg-base-100">
              <div class="h-full w-3/4 rounded-full bg-primary" />
            </div>
            <div class="h-2 w-4/5 rounded-full bg-base-100" /><div class="h-2 w-2/3 rounded-full bg-base-100" />
          </div>
        </section>
      </div>
    </div>
    """
  end

  defp ai_settings_preview(assigns) do
    ~H"""
    <div class="flex h-full flex-col">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-lg font-bold">{gettext("AI settings")}</h2>
          <p class="mt-0.5 text-[9px] text-base-content/45">
            {gettext("Control how Konevo writes for your team")}
          </p>
        </div>
        <span class="btn btn-primary btn-xs gap-1 shadow-none">
          <.icon name="icon-[tabler--device-floppy]" class="size-3" />{gettext("Saved")}
        </span>
      </div>

      <section class="mt-4 min-h-0 flex-1 overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm">
        <div class="flex items-center gap-2 border-b border-base-content/10 bg-base-200/35 px-3 py-2.5">
          <span class="flex size-7 items-center justify-center rounded-md bg-primary/10 text-primary">
            <.icon name="icon-[tabler--sparkles]" class="size-3.5" />
          </span>
          <div>
            <p class="text-[10px] font-semibold">{gettext("AI behavior")}</p>
            <p class="mt-0.5 text-[8px] text-base-content/45">
              {gettext("Context and rules used for every AI draft")}
            </p>
          </div>
        </div>
        <div class="grid grid-cols-2 gap-2 p-2.5 sm:gap-3 sm:p-3">
          <div>
            <p class="mb-1 text-[9px] font-medium text-base-content/60">{gettext("AI context")}</p>
            <div class="h-24 overflow-hidden rounded-lg border border-base-content/12 bg-base-200/30 p-2 text-[8px] leading-[0.875rem] text-base-content/65 sm:min-h-24 sm:h-auto sm:p-2.5 sm:text-[9px] sm:leading-4">
              {gettext(
                "We are Acme Studio, a B2B design partner. Prioritize project timelines, pricing questions, and clear next steps."
              )}
            </div>
          </div>
          <div>
            <p class="mb-1 text-[9px] font-medium text-base-content/60">
              {gettext("Email instructions")}
            </p>
            <div class="h-24 overflow-hidden rounded-lg border border-base-content/12 bg-base-200/30 p-2 text-[8px] leading-[0.875rem] text-base-content/65 sm:min-h-24 sm:h-auto sm:p-2.5 sm:text-[9px] sm:leading-4">
              {gettext(
                "Keep replies warm and concise. Confirm dates from the thread and ask one clear follow-up when needed."
              )}
            </div>
          </div>
          <div class="col-span-2">
            <div class="grid grid-cols-3 gap-2">
              <div class="rounded-md border border-base-content/12 bg-base-100 px-2 py-1.5">
                <p class="text-[8px] text-base-content/45">{gettext("Tone")}</p>
                <p class="mt-1 text-[9px] font-semibold">{gettext("Warm")}</p>
              </div>
              <div class="rounded-md border border-base-content/12 bg-base-100 px-2 py-1.5">
                <p class="text-[8px] text-base-content/45">{gettext("Language")}</p>
                <p class="mt-1 text-[9px] font-semibold">{gettext("English")}</p>
              </div>
              <div class="rounded-md border border-base-content/12 bg-base-100 px-2 py-1.5">
                <p class="text-[8px] text-base-content/45">{gettext("Length")}</p>
                <p class="mt-1 text-[9px] font-semibold">{gettext("Concise")}</p>
              </div>
            </div>
          </div>
          <div class="col-span-2 mb-2 rounded-lg border border-primary/20 bg-primary/5 p-2 sm:mb-0 sm:p-2.5">
            <div class="flex items-center gap-1.5 text-[8px] font-semibold text-primary sm:text-[9px]">
              <.icon name="icon-[tabler--mail-ai]" class="size-3 sm:size-3.5" />
              {gettext("What AI uses when it drafts")}
            </div>
            <div class="mt-2 hidden grid-cols-3 gap-1.5 text-[8px] text-base-content/60 sm:grid">
              <span class="rounded bg-base-100 px-1.5 py-1">{gettext("Email thread")}</span>
              <span class="rounded bg-base-100 px-1.5 py-1">{gettext("Your context")}</span>
              <span class="rounded bg-base-100 px-1.5 py-1">{gettext("Writing rules")}</span>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  attr(:eyebrow, :string, required: true)
  attr(:title, :string, required: true)
  attr(:icon, :string, required: true)

  defp preview_heading(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-3">
      <div>
        <p class="text-[10px] font-semibold uppercase tracking-[0.16em] text-primary">{@eyebrow}</p>
        <h2 class="mt-1 text-base font-bold sm:text-lg">{@title}</h2>
      </div>
      <span class="flex size-8 items-center justify-center rounded-lg border border-base-content/10 bg-base-100 text-primary">
        <.icon name={@icon} class="size-4" />
      </span>
    </div>
    """
  end

  attr(:initials, :string, required: true)
  attr(:name, :string, required: true)
  attr(:subject, :string, required: true)
  attr(:selected, :boolean, default: false)

  defp inbox_item(assigns) do
    ~H"""
    <div class={["flex gap-2 rounded-md p-2", @selected && "bg-primary/10"]}>
      <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-base-200 text-[8px] font-bold text-primary">
        {@initials}
      </span>
      <span class="min-w-0">
        <span class="block truncate text-[9px] font-bold">{@name}</span><span class="block truncate text-[8px] text-base-content/45">{@subject}</span>
      </span>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:count, :string, required: true)
  attr(:active, :boolean, default: false)

  defp inbox_view(assigns) do
    ~H"""
    <span class={[
      "flex items-center gap-1.5 rounded-lg px-2 py-1.5 text-[8px] font-medium",
      @active && "bg-primary/10 text-primary",
      !@active && "text-base-content/60"
    ]}>
      <.icon name={@icon} class="size-3" /><span class="truncate">{@label}</span><span
        :if={@count != ""}
        class="ml-auto rounded-full bg-base-content/8 px-1 text-[7px]"
      >{@count}</span>
    </span>
    """
  end

  attr(:sender, :string, required: true)
  attr(:subject, :string, required: true)
  attr(:preview, :string, required: true)
  attr(:time, :string, required: true)
  attr(:unread, :boolean, default: false)

  defp inbox_list_row(assigns) do
    ~H"""
    <div class={["grid grid-cols-[minmax(0,1fr)_auto] gap-x-2 px-3 py-2.5", @unread && "bg-primary/4"]}>
      <div class="min-w-0">
        <p class={["truncate text-[9px]", @unread && "font-bold"]}>
          {@sender}<span class="font-normal text-base-content/45"> · {@subject}</span>
        </p>
        <p class="mt-0.5 truncate text-[8px] text-base-content/45">{@preview}</p>
      </div>
      <span class={[
        "text-[8px]",
        @unread && "font-semibold text-primary",
        !@unread && "text-base-content/40"
      ]}>
        {@time}
      </span>
    </div>
    """
  end

  attr(:initials, :string, required: true)
  attr(:name, :string, required: true)
  attr(:email, :string, required: true)
  attr(:company, :string, required: true)
  attr(:touch, :string, required: true)

  defp contact_item(assigns) do
    ~H"""
    <div class="grid grid-cols-[1.25fr_.8fr_.65fr] items-center border-t border-base-content/8 px-3 py-2">
      <span class="flex min-w-0 items-center gap-2">
        <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary/10 text-[8px] font-bold text-primary">
          {@initials}
        </span>
        <span class="min-w-0">
          <span class="block truncate text-[9px] font-bold">{@name}</span><span class="block truncate text-[8px] text-base-content/45">{@email}</span>
        </span>
      </span>
      <span class="truncate text-[9px] text-base-content/60">{@company}</span><span class="text-[8px] text-base-content/45">{@touch}</span>
    </div>
    """
  end

  attr(:initials, :string, required: true)
  attr(:name, :string, required: true)
  attr(:email, :string, required: true)
  attr(:company, :string, required: true)
  attr(:category, :string, required: true)

  defp contact_table_row(assigns) do
    ~H"""
    <tr class="border-b border-base-content/8 transition-colors hover:bg-base-200/40">
      <td class="px-3 py-1.5">
        <span class="flex min-w-0 items-center gap-2">
          <span class="flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/10 text-[7px] font-bold text-primary">
            {@initials}
          </span>
          <span class="truncate text-[9px] font-semibold">{@name}</span>
        </span>
      </td>
      <td class="truncate px-3 py-1.5 text-[8px] text-base-content/60">{@email}</td>
      <td class="truncate px-3 py-1.5 text-[8px] text-base-content/60">{@company}</td>
      <td class="px-3 py-1.5 text-[8px] text-base-content/60">{@category}</td>
    </tr>
    """
  end

  attr(:name, :string, required: true)
  attr(:website, :string, required: true)
  attr(:industry, :string, required: true)
  attr(:contacts, :string, required: true)
  attr(:created, :string, required: true)

  defp company_item(assigns) do
    ~H"""
    <div class="grid grid-cols-[1.2fr_.7fr_.65fr_.45fr] items-center border-b border-base-content/8 px-3 py-2">
      <span class="min-w-0">
        <span class="block truncate text-[9px] font-semibold">{@name}</span><span class="block truncate text-[8px] text-base-content/45">{@website}</span>
      </span>
      <span class="truncate text-[9px] text-base-content/60">{@industry}</span><span class="text-[9px] text-base-content/60">{@contacts}</span><span class="text-[8px] text-base-content/45">{@created}</span>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:amount, :string, required: true)
  attr(:cards, :list, required: true)
  attr(:color, :string, default: "#0ea5e9")

  defp deal_column(assigns) do
    ~H"""
    <section class="min-w-0 rounded-xl bg-base-200/55 p-2">
      <div class="flex items-center justify-between gap-1">
        <p class="truncate text-[9px] font-bold">{@title}</p>
        <span class="size-1.5 rounded-full" style={"background-color: #{@color}"} />
      </div>
      <p class="mt-1 text-[8px] text-base-content/45">{@amount}</p>
      <div class="mt-2 space-y-2">
        <%= for {name, value} <- @cards do %>
          <div class="rounded-md border border-base-content/8 bg-base-100 p-2 shadow-sm">
            <p class="truncate text-[9px] font-semibold">{name}</p>
            <p class="mt-2 text-[9px] font-bold text-primary">{value}</p>
            <div class="mt-2 h-1 rounded-full bg-primary/15">
              <div class="h-full w-2/3 rounded-full bg-primary" />
            </div>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  defp calendar_month_grid(assigns) do
    assigns =
      assign(assigns, :days, [
        %{date: "29", muted: true, events: []},
        %{date: "30", muted: true, events: []},
        %{date: "1", muted: false, events: []},
        %{date: "2", muted: false, events: []},
        %{date: "3", muted: false, events: []},
        %{date: "4", muted: false, events: []},
        %{date: "5", muted: false, events: []},
        %{date: "6", muted: false, events: [{gettext("Team standup"), "primary"}]},
        %{date: "7", muted: false, events: []},
        %{date: "8", muted: false, events: [{gettext("Acme kickoff"), "success"}]},
        %{date: "9", muted: false, events: []},
        %{date: "10", muted: false, events: []},
        %{date: "11", muted: false, events: []},
        %{date: "12", muted: false, events: []},
        %{date: "13", muted: false, events: []},
        %{date: "14", muted: false, events: [{gettext("Ava onboarding"), "primary"}]},
        %{date: "15", muted: false, events: [{gettext("Proposal review"), "warning"}]},
        %{date: "16", muted: false, events: [{gettext("Pipeline check"), "error"}]},
        %{date: "17", muted: false, events: [{gettext("Northstar demo"), "success"}]},
        %{date: "18", muted: false, events: [{gettext("Weekly wrap"), "warning"}]},
        %{date: "19", muted: false, events: []},
        %{date: "20", muted: false, events: []},
        %{date: "21", muted: false, events: []},
        %{date: "22", muted: false, events: [{gettext("Follow up"), "primary"}]},
        %{date: "23", muted: false, events: []},
        %{date: "24", muted: false, events: []},
        %{date: "25", muted: false, events: []},
        %{date: "26", muted: false, events: []},
        %{date: "27", muted: false, events: []},
        %{date: "28", muted: false, events: []},
        %{date: "29", muted: false, events: []},
        %{date: "30", muted: false, events: []},
        %{date: "31", muted: false, events: []},
        %{date: "1", muted: true, events: []},
        %{date: "2", muted: true, events: []}
      ])

    ~H"""
    <div class="flex min-h-0 flex-1 flex-col overflow-hidden">
      <div class="grid grid-cols-7 border-b border-base-content/8 text-center text-[7px] font-semibold uppercase tracking-wide text-base-content/45">
        <span class="py-1">{gettext("Mon")}</span>
        <span class="py-1">{gettext("Tue")}</span>
        <span class="py-1">{gettext("Wed")}</span>
        <span class="py-1">{gettext("Thu")}</span>
        <span class="py-1">{gettext("Fri")}</span>
        <span class="py-1">{gettext("Sat")}</span>
        <span class="py-1">{gettext("Sun")}</span>
      </div>
      <div class="grid min-h-0 flex-1 grid-cols-7 grid-rows-5 border-l border-t border-base-content/8">
        <div
          :for={day <- @days}
          class={[
            "min-w-0 border-b border-r border-base-content/8 p-1",
            day.muted && "bg-base-200/25"
          ]}
        >
          <span class={[
            "mx-auto flex size-4 items-center justify-center rounded-full text-[7px] font-semibold text-base-content/60",
            day.date == "14" && !day.muted && "bg-primary text-primary-content",
            day.muted && "text-base-content/30"
          ]}>
            {day.date}
          </span>
          <div class="mt-1 space-y-0.5">
            <span
              :for={{event, tone} <- day.events}
              class={[
                "block truncate rounded px-1 py-0.5 text-[6px] font-semibold leading-3",
                calendar_tone(tone)
              ]}
            >
              {event}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr(:day, :string, required: true)
  attr(:date, :string, required: true)
  attr(:events, :list, required: true)

  defp calendar_day(assigns) do
    ~H"""
    <div class="min-h-52 border-b border-r border-base-content/8 p-1.5">
      <p class="text-center text-[8px] font-bold text-base-content/45">{@day}</p>
      <p class="mt-1 text-center text-[10px] font-bold">{@date}</p>
      <div class="mt-3 space-y-1">
        <%= for {event, tone} <- @events do %>
          <div class={["rounded px-1.5 py-1 text-[8px] font-semibold leading-3", calendar_tone(tone)]}>
            {event}
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr(:icon, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:tone, :string, required: true)

  defp calendar_metric(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/10 bg-base-100 p-2">
      <span class={[
        "inline-flex size-5 items-center justify-center rounded-md",
        calendar_summary_tone(@tone)
      ]}>
        <.icon name={@icon} class="size-3" />
      </span>
      <p class="mt-1 text-sm font-bold leading-none">{@value}</p>
      <p class="mt-1 truncate text-[8px] text-base-content/45">{@label}</p>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:meta, :string, required: true)
  attr(:tone, :string, required: true)

  defp task_item(assigns) do
    ~H"""
    <div class="flex items-center gap-2 py-2.5">
      <span class={["size-4 shrink-0 rounded border-2", task_tone(@tone)]} />
      <span class="min-w-0 flex-1">
        <span class="block truncate text-[10px] font-semibold">{@title}</span><span class="block truncate text-[8px] text-base-content/45">{@meta}</span>
      </span>
      <.icon name="icon-[tabler--dots]" class="size-3 text-base-content/35" />
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:status, :string, required: true)
  attr(:priority, :string, required: true)
  attr(:due, :string, required: true)
  attr(:type, :string, required: true)
  attr(:depth, :integer, required: true)
  attr(:children, :boolean, default: false)

  defp task_tree_preview_row(assigns) do
    ~H"""
    <div class="grid grid-cols-[1.45fr_.6fr_.7fr_.55fr] items-center divide-x divide-base-content/8 border-b border-base-content/8 px-3 py-2.5 transition-colors hover:bg-base-200/40">
      <span class="flex min-w-0 items-center gap-1.5" style={"padding-left: #{@depth * 0.85}rem"}>
        <span
          :if={@children}
          class="flex size-4 shrink-0 items-center justify-center rounded bg-primary/10 text-primary"
        >
          <.icon name="icon-[tabler--chevron-down]" class="size-3" />
        </span>
        <span :if={!@children} class="size-4 shrink-0" />
        <span class={[
          @type == "epic" && "border-warning/45 bg-warning/10 text-warning",
          @type != "epic" && "border-primary/35 bg-primary/8 text-primary",
          "flex size-5 shrink-0 items-center justify-center rounded-md border"
        ]}>
          <.icon
            name={if(@type == "epic", do: "icon-[tabler--crown]", else: "icon-[tabler--menu-2]")}
            class="size-3"
          />
        </span>
        <span class="truncate text-[9px] font-semibold">{@title}</span>
        <.icon name="icon-[tabler--dots-vertical]" class="ml-auto size-3 text-base-content/35" />
      </span>
      <span class="px-2">
        <span class={[
          "inline-flex items-center gap-1 rounded-md border px-1.5 py-1 text-[8px] font-medium leading-none",
          @status == "In progress" && "border-[#8b5cf6]/35 bg-[#8b5cf6]/12 text-[#8b5cf6]",
          @status == "Done" && "border-[#10b981]/35 bg-[#10b981]/12 text-[#10b981]",
          @status not in ["In progress", "Done"] &&
            "border-[#0ea5e9]/35 bg-[#0ea5e9]/12 text-[#0ea5e9]"
        ]}>
          <.icon
            name={
              if(@status == "Done",
                do: "icon-[tabler--circle-check-filled]",
                else:
                  if(@status == "In progress",
                    do: "icon-[tabler--circle-half-2]",
                    else: "icon-[tabler--circle]"
                  )
              )
            }
            class="size-2.5"
          />
          {@status}
        </span>
      </span>
      <span class="px-2">
        <span class={[
          "inline-flex items-center gap-1 rounded-md border px-1.5 py-1 text-[8px] font-medium leading-none",
          @priority == "Urgent" && "border-[#ef4444]/35 bg-[#ef4444]/12 text-[#ef4444]",
          @priority == "High" && "border-[#f97316]/35 bg-[#f97316]/12 text-[#f97316]",
          @priority == "Low" && "border-[#64748b]/35 bg-[#64748b]/12 text-[#64748b]",
          @priority not in ["Urgent", "High", "Low"] &&
            "border-[#3b82f6]/35 bg-[#3b82f6]/12 text-[#3b82f6]"
        ]}>
          <.icon name="icon-[tabler--flag-filled]" class="size-2.5" />
          {@priority}
        </span>
      </span>
      <span class="px-2 text-[8px] text-base-content/45">{@due}</span>
    </div>
    """
  end

  attr(:page, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:label, :string, required: true)
  attr(:active_page, :string, required: true)
  attr(:badge, :string, default: nil)

  defp preview_nav(assigns) do
    ~H"""
    <span
      id={"test-landing-preview-nav-#{@page}"}
      class={[
        "flex w-full items-center justify-between rounded-md px-2 py-2 text-[11px] text-left transition-colors",
        @active_page == @page && "bg-primary/12 font-semibold text-primary",
        @active_page != @page && "text-base-content/55 hover:bg-base-content/5"
      ]}
    >
      <span class="flex items-center gap-2">
        <.icon name={@icon} class="size-4" /><span class="hidden sm:inline">{@label}</span>
      </span>
      <span
        :if={@badge}
        class="hidden rounded-full bg-primary px-1.5 text-[9px] font-bold text-primary-content sm:inline"
      >
        {@badge}
      </span>
    </span>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:tone, :string, required: true)

  defp preview_metric(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-content/8 bg-base-100 p-2.5">
      <span class={["block size-1.5 rounded-full", metric_tone(@tone)]} />
      <p class="mt-2 text-sm font-bold leading-none">{@value}</p>
      <p class="mt-1 truncate text-[9px] text-base-content/50">{@label}</p>
    </div>
    """
  end

  attr(:initials, :string, required: true)
  attr(:name, :string, required: true)
  attr(:detail, :string, required: true)
  attr(:age, :string, required: true)

  defp preview_row(assigns) do
    ~H"""
    <div class="flex items-center gap-2 py-2">
      <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-primary/10 text-[8px] font-bold text-primary">
        {@initials}
      </span>
      <span class="min-w-0 flex-1">
        <span class="block truncate text-[10px] font-semibold">{@name}</span><span class="block truncate text-[9px] text-base-content/45">{@detail}</span>
      </span>
      <span class="text-[9px] text-base-content/45">{@age}</span>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:count, :string, required: true)

  defp pipeline_column(assigns) do
    ~H"""
    <div class="min-w-0 rounded-md bg-base-200/60 p-1.5">
      <p class="truncate text-[8px] font-semibold text-base-content/55">{@label}</p>
      <p class="mt-1 text-[10px] font-bold">{@value}</p>
      <div class="mt-2 h-1 rounded-full bg-primary/25">
        <div class="h-1 w-2/3 rounded-full bg-primary" />
      </div>
      <p class="mt-1 text-[8px] text-base-content/45">{@count} {gettext("deals")}</p>
    </div>
    """
  end

  defp preview_copy("dashboard") do
    %{
      label: gettext("Dashboard"),
      title: gettext("Self-hosted AI CRM, built around your inbox"),
      description:
        gettext(
          "Turn customer emails into contacts, tasks, and follow-ups—while AI handles the next step with you in control."
        ),
      icon: "icon-[tabler--layout-dashboard]",
      position: "01"
    }
  end

  defp preview_copy("inbox") do
    %{
      label: gettext("Inbox"),
      title: gettext("Every reply, right on time."),
      description:
        gettext(
          "Keep customer conversations, their history, and the next best action together in one focused shared inbox."
        ),
      icon: "icon-[tabler--inbox]",
      position: "02"
    }
  end

  defp preview_copy("contacts") do
    %{
      label: gettext("Contacts"),
      title: gettext("Every relationship, remembered."),
      description: gettext("Keep every person, company, and follow-up in one shared view."),
      icon: "icon-[tabler--users]",
      position: "03"
    }
  end

  defp preview_copy("companies") do
    %{
      label: gettext("Companies"),
      title: gettext("Every company, in context."),
      description:
        gettext(
          "Keep company records and people connected, so every team member has the full picture."
        ),
      icon: "icon-[tabler--building]",
      position: "04"
    }
  end

  defp preview_copy("deals") do
    %{
      label: gettext("Deals"),
      title: gettext("Turn follow-through into forecast."),
      description:
        gettext(
          "Give every opportunity a clear stage, owner, and next move—then see where your revenue is gaining momentum."
        ),
      icon: "icon-[tabler--briefcase]",
      position: "05"
    }
  end

  defp preview_copy("calendar") do
    %{
      label: gettext("Calendar"),
      title: gettext("Make room for the work that matters."),
      description:
        gettext(
          "Bring customer moments, team meetings, and important deadlines into one calm weekly view."
        ),
      icon: "icon-[tabler--calendar-week]",
      position: "06"
    }
  end

  defp preview_copy("tasks") do
    %{
      label: gettext("Tasks"),
      title: gettext("Know exactly what to do next."),
      description:
        gettext(
          "Turn promises into clear, accountable work so no customer, handoff, or follow-up slips through the cracks."
        ),
      icon: "icon-[tabler--checkbox]",
      position: "07"
    }
  end

  defp preview_copy(_page) do
    %{
      label: gettext("AI-first CRM for service teams"),
      title: gettext("Your inbox knows what to do next."),
      description:
        gettext(
          "Konevo turns customer conversations into contacts, tasks, and follow-ups—so your team can protect every lead without the CRM busywork."
        ),
      icon: "icon-[tabler--sparkles]",
      position: "01"
    }
  end

  defp cycle_preview(current_page, direction) do
    current_index = Enum.find_index(@preview_pages, &(&1 == current_page)) || 0
    next_index = rem(current_index + direction + length(@preview_pages), length(@preview_pages))
    Enum.at(@preview_pages, next_index)
  end

  defp schedule_preview_advance(socket) do
    socket = cancel_preview_advance(socket)
    token = make_ref()
    timer_ref = Process.send_after(self(), {:advance_preview, token}, @preview_autoplay_interval)

    assign(socket, preview_timer_ref: timer_ref, preview_timer_token: token)
  end

  defp cancel_preview_advance(socket) do
    if socket.assigns.preview_timer_ref,
      do: Process.cancel_timer(socket.assigns.preview_timer_ref)

    assign(socket, preview_timer_ref: nil, preview_timer_token: nil)
  end

  defp calendar_tone("primary"), do: "bg-[#0ea5e9]/14 text-[#0284c7]"
  defp calendar_tone("success"), do: "bg-[#10b981]/14 text-[#059669]"
  defp calendar_tone("warning"), do: "bg-[#f59e0b]/14 text-[#b45309]"
  defp calendar_tone(_tone), do: "bg-[#dc2626]/14 text-[#dc2626]"

  defp calendar_summary_tone("task"), do: "bg-[#0ea5e9]/14 text-[#0284c7]"
  defp calendar_summary_tone("contact"), do: "bg-[#6366f1]/14 text-[#4f46e5]"
  defp calendar_summary_tone("company"), do: "bg-[#10b981]/14 text-[#059669]"
  defp calendar_summary_tone(_tone), do: "bg-error/13 text-error"

  defp task_tone("error"), do: "border-error"
  defp task_tone("warning"), do: "border-warning"
  defp task_tone("success"), do: "border-success"
  defp task_tone(_tone), do: "border-primary"

  attr(:number, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)

  defp feature_card(assigns) do
    ~H"""
    <article class="group rounded-2xl border border-base-content/10 bg-base-100 p-6 transition duration-200 hover:-translate-y-1 hover:border-primary/30 hover:shadow-lg hover:shadow-base-content/5">
      <div class="flex items-center justify-between">
        <span class="text-sm font-bold text-primary">{@number}</span><span class="flex size-10 items-center justify-center rounded-xl bg-primary/10 text-primary transition group-hover:bg-primary group-hover:text-primary-content"><.icon
          name={@icon}
          class="size-5"
        /></span>
      </div>
      <h3 class="mt-8 text-lg font-bold">{@title}</h3>
      <p class="mt-2 leading-7 text-base-content/60">{@description}</p>
    </article>
    """
  end

  attr(:id, :string, required: true)
  attr(:number, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  slot(:inner_block, required: true)

  defp installation_step(assigns) do
    ~H"""
    <article
      id={@id}
      class="flex min-w-0 flex-col rounded-2xl border border-base-content/10 bg-base-100 p-5 shadow-sm transition duration-200 hover:-translate-y-1 hover:border-primary/30 hover:shadow-lg hover:shadow-base-content/5 sm:p-6"
    >
      <div class="flex items-center justify-between gap-4">
        <span class="text-sm font-bold text-primary">{@number}</span>
        <span class="flex size-10 items-center justify-center rounded-xl bg-primary/10 text-primary">
          <.icon name={@icon} class="size-5" />
        </span>
      </div>
      <h3 class="mt-7 text-lg font-bold">{@title}</h3>
      <p class="mt-2 min-h-20 leading-7 text-base-content/60">{@description}</p>
      <div class="mt-6 min-w-0">{render_slot(@inner_block)}</div>
    </article>
    """
  end

  attr(:id, :string, required: true)
  attr(:code, :string, required: true)

  defp installation_code_block(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-xl border border-base-content/10 bg-neutral shadow-inner">
      <div class="flex items-center justify-between border-b border-neutral-content/10 px-3 py-2">
        <span class="flex items-center gap-1.5 text-[0.6875rem] font-medium text-neutral-content/60">
          <.icon name="icon-[tabler--terminal-2]" class="size-3.5" />
          {gettext("Terminal")}
        </span>
        <button
          id={"#{@id}-copy"}
          type="button"
          phx-hook=".CopyInstallationCommand"
          phx-update="ignore"
          data-copy-target={@id}
          data-copy-label={gettext("Copy")}
          data-copied-label={gettext("Copied")}
          data-copy-error-label={gettext("Copy failed")}
          aria-label={gettext("Copy")}
          class="btn btn-ghost btn-xs gap-1.5 text-neutral-content/75 transition-colors hover:bg-neutral-content/10 hover:text-neutral-content disabled:cursor-wait"
        >
          <.icon data-copy-icon name="icon-[tabler--copy]" class="size-3.5" />
          <.icon data-check-icon name="icon-[tabler--check]" class="hidden size-3.5" />
          <span data-copy-label>{gettext("Copy")}</span>
        </button>
      </div>
      <pre id={@id} class="overflow-x-auto p-4 font-mono text-xs leading-6 text-neutral-content"><code>{@code}</code></pre>
    </div>
    """
  end

  defp installation_download_commands do
    [
      "# Install Docker Engine and the Docker Compose plugin first.",
      "sudo apt update && sudo apt install -y curl jq git",
      "sudo adduser --system --group --home /opt/konevo --shell /usr/sbin/nologin konevo-deploy",
      "sudo install -d -o konevo-deploy -g konevo-deploy /opt/konevo/app",
      "",
      "sudo -u konevo-deploy git clone https://github.com/FilipPauco/konevo.git /opt/konevo/app"
    ]
    |> Enum.join("\n")
  end

  defp installation_configuration_commands do
    [
      "# Keep production secrets only on this server.",
      "sudo install -o root -g konevo-deploy -m 640 /opt/konevo/app/.env.example /opt/konevo/app/.env",
      "sudoedit /opt/konevo/app/.env",
      "",
      "# In /opt/konevo/app/.env, set APP_IMAGE=ghcr.io/filippauco/konevo:vX.Y.Z to the published release you want to run.",
      "",
      "# Optional: create this only if Konevo should automatically deploy each new GitHub Release from this repository.",
      "sudo install -d -o root -g root -m 755 /etc/konevo",
      "sudo install -o root -g root -m 644 /opt/konevo/app/deploy/docker/deploy.env.example /etc/konevo/deploy.env",
      "sudoedit /etc/konevo/deploy.env",
      "APP_IMAGE_REPOSITORY=ghcr.io/filippauco/konevo",
      "GITHUB_REPOSITORY=FilipPauco/konevo"
    ]
    |> Enum.join("\n")
  end

  defp installation_launch_commands do
    [
      "# Start the release selected by APP_IMAGE in /opt/konevo/app/.env.",
      "sudo install -d -o 65534 -g 65534 -m 750 /opt/konevo/uploads",
      "sudo install -d -o konevo-deploy -g konevo-deploy -m 750 /var/lib/konevo",
      "sudo docker compose --env-file /opt/konevo/app/.env \\",
      "  -f /opt/konevo/app/deploy/docker/compose.yaml up -d",
      "",
      "sudo docker compose --env-file /opt/konevo/app/.env \\",
      "  -f /opt/konevo/app/deploy/docker/compose.yaml \\",
      ~S{  exec app env -u PHX_SERVER bin/konevo eval 'IO.inspect(Konevo.Release.create_owner(), label: "Owner creation")'},
      "",
      "# Now your app runs at https://your-domain.example",
      "",
      "# Optional: enable this to check the configured repository for new GitHub Releases and deploy them automatically.",
      "sudo install -o root -g root -m 755 /opt/konevo/app/deploy/docker/konevo-deploy.sh /usr/local/sbin/konevo-deploy",
      "sudo install -o root -g root -m 644 /opt/konevo/app/deploy/docker/konevo-deploy.service /etc/systemd/system/konevo-deploy.service",
      "sudo install -o root -g root -m 644 /opt/konevo/app/deploy/docker/konevo-deploy.timer /etc/systemd/system/konevo-deploy.timer",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable --now konevo-deploy.timer",
      "sudo systemctl start konevo-deploy.service"
    ]
    |> Enum.join("\n")
  end

  attr(:id, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:badge, :string, required: true)

  defp technology_card(assigns) do
    ~H"""
    <article
      id={@id}
      class="rounded-xl border border-base-content/10 bg-base-100 p-4 shadow-sm transition duration-200 hover:-translate-y-1 hover:border-primary/30 hover:shadow-lg hover:shadow-base-content/5"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div class="flex min-w-0 items-start gap-3">
          <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <.icon name={@icon} class="size-5" />
          </div>
          <div class="min-w-0">
            <h3 class="text-sm font-semibold text-base-content">{@title}</h3>
            <p class="mt-1 text-sm leading-6 text-base-content/60">{@description}</p>
          </div>
        </div>
        <span class="badge badge-sm shrink-0 self-start rounded-md border border-primary/30 bg-primary/10 text-primary">
          {@badge}
        </span>
      </div>
    </article>
    """
  end

  defp metric_tone("warning"), do: "bg-warning"
  defp metric_tone("error"), do: "bg-error"
  defp metric_tone("success"), do: "bg-success"
  defp metric_tone(_tone), do: "bg-primary"

  defp mobile_tone_surface("warning"), do: "bg-warning/12 text-warning"
  defp mobile_tone_surface("error"), do: "bg-error/12 text-error"
  defp mobile_tone_surface("success"), do: "bg-success/12 text-success"
  defp mobile_tone_surface(_tone), do: "bg-primary/12 text-primary"
end
