defmodule KonevoWeb.WorkflowDemoLive do
  use KonevoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("AI Workflows in Action | Konevo"))
     |> assign(
       :seo_description,
       gettext("See how Konevo turns email into review-ready replies, tasks, and follow-ups.")
     )
     |> assign(:seo_json_ld, Seo.software_application_json_ld())
     |> assign(:seo_robots, "index, follow")
     |> assign(:seo_url, Seo.page_url("/demo"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="workflow-demo" class="min-h-screen overflow-hidden bg-base-100 text-base-content">
      <section class="relative isolate overflow-hidden">
        <div aria-hidden="true" class="landing-grid absolute inset-0 -z-10 opacity-55" />
        <div
          aria-hidden="true"
          class="landing-glow absolute -right-48 -top-52 -z-10 size-[42rem] rounded-full"
        />
        <header class="mx-auto flex max-w-7xl items-center justify-between px-5 py-3 sm:px-8 sm:py-5 lg:px-10">
          <a
            id="workflow-demo-brand"
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
            id="workflow-demo-navigation"
            class="hidden items-center gap-6 text-sm font-semibold text-base-content/65 md:flex"
            aria-label={gettext("Marketing navigation")}
          >
            <a
              href={~p"/#product"}
              class="px-1 py-2 transition-colors duration-200 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              {gettext("Product")}
            </a>
            <a
              href={~p"/#how-it-works"}
              class="px-1 py-2 transition-colors duration-200 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              {gettext("How it works")}
            </a>
            <a
              href={~p"/#installation"}
              class="px-1 py-2 transition-colors duration-200 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              {gettext("Installation")}
            </a>
            <a
              href={~p"/#contact"}
              class="px-1 py-2 transition-colors duration-200 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              {gettext("Contact")}
            </a>
          </nav>

          <div class="flex items-center gap-2 sm:gap-3">
            <button
              id="workflow-demo-theme-toggle"
              type="button"
              phx-hook=".WorkflowDemoThemeToggle"
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
              id="workflow-demo-view-examples"
              navigate={~p"/demo"}
              class="btn btn-primary btn-sm w-9 min-w-9 px-0 font-semibold shadow-lg shadow-primary/20 transition-all hover:-translate-y-0.5 hover:shadow-primary/30 sm:w-auto sm:min-w-0 sm:gap-2 sm:px-4"
              aria-current="page"
            >
              <.icon name="icon-[tabler--sparkles]" class="size-4" />
              <span class="hidden sm:inline">{gettext("View examples")}</span>
              <span class="sr-only sm:hidden">{gettext("View examples")}</span>
            </.link>
          </div>
        </header>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".WorkflowDemoThemeToggle">
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

        <section class="relative border-b border-base-content/10">
          <div class="mx-auto max-w-4xl px-5 py-20 text-center sm:px-8 sm:py-28 lg:px-10">
            <span class="badge badge-primary badge-outline gap-1.5 rounded-full px-3 py-3 text-xs font-semibold">
              <.icon name="icon-[tabler--sparkles]" class="size-3.5" />
              {gettext("AI Workflows in Action")}
            </span>
            <h1 class="mt-5 text-4xl font-bold tracking-[-0.045em] text-base-content sm:text-5xl lg:text-6xl">
              {gettext("Every important email gets a clear next step.")}
            </h1>
            <p class="mx-auto mt-5 max-w-2xl text-base leading-7 text-base-content/65 sm:text-lg">
              {gettext(
                "See how Konevo turns customer email into review-ready replies, actionable tasks, and considerate follow-ups."
              )}
            </p>
          </div>
        </section>
      </section>

      <section
        id="workflow-demo-configuration"
        class="mx-auto max-w-7xl px-5 py-16 sm:px-8 lg:px-10 lg:py-24"
      >
        <div class="mx-auto max-w-3xl">
          <p class="text-sm font-semibold text-primary">{gettext("DEMO CONFIGURATION")}</p>
          <h2 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
            {gettext("Guidance that stays grounded in the customer conversation.")}
          </h2>
          <p class="mt-4 max-w-xl leading-7 text-base-content/65">
            {gettext(
              "The same shared context guides every workflow, while email and task rules keep each outcome useful and consistent."
            )}
          </p>

          <dl class="mt-7 space-y-4">
            <div class="rounded-xl border border-base-content/10 bg-base-200/45 p-4">
              <dt class="flex items-center gap-2 text-sm font-semibold">
                <span class="flex size-7 items-center justify-center rounded-lg bg-primary/10 text-primary">
                  <.icon name="icon-[tabler--building]" class="size-3.5" />
                </span>
                {gettext("General context")}
              </dt>
              <dd class="mt-2 text-sm leading-6 text-base-content/65">
                {gettext(
                  "Northstar Coffee sells commercial espresso machines. The AI never invents prices, stock, delivery dates, or warranties."
                )}
              </dd>
            </div>
            <div class="rounded-xl border border-base-content/10 bg-base-200/45 p-4">
              <dt class="flex items-center gap-2 text-sm font-semibold">
                <span class="flex size-7 items-center justify-center rounded-lg bg-primary/10 text-primary">
                  <.icon name="icon-[tabler--mail]" class="size-3.5" />
                </span>
                {gettext("Email replies")}
              </dt>
              <dd class="mt-2 text-sm leading-6 text-base-content/65">
                {gettext(
                  "Professional, concise, and in the incoming email's language. When details are missing, the AI checks and asks one clear question."
                )}
              </dd>
            </div>
            <div class="rounded-xl border border-base-content/10 bg-base-200/45 p-4">
              <dt class="flex items-center gap-2 text-sm font-semibold">
                <span class="flex size-7 items-center justify-center rounded-lg bg-primary/10 text-primary">
                  <.icon name="icon-[tabler--checkbox]" class="size-3.5" />
                </span>
                {gettext("Task extraction")}
              </dt>
              <dd class="mt-2 text-sm leading-6 text-base-content/65">
                {gettext(
                  "Related unresolved requests become one actionable task, with no invented deadline or urgency."
                )}
              </dd>
            </div>
          </dl>
        </div>
        <figure class="mx-auto mt-10 max-w-5xl overflow-hidden rounded-2xl border border-base-content/10 bg-base-200/50 p-3 shadow-xl shadow-base-content/10 sm:p-4">
          <img
            src={~p"/images/automation_ai/settings.png"}
            alt={gettext("AI configuration in Konevo Settings")}
            class="w-full rounded-xl"
          />
        </figure>
      </section>

      <section id="workflow-demo-examples" class="border-y border-base-content/10 bg-base-200/35">
        <div class="mx-auto max-w-7xl px-5 py-16 sm:px-8 lg:px-10 lg:py-24">
          <div class="max-w-2xl">
            <p class="text-sm font-semibold text-primary">{gettext("THREE WORKFLOWS")}</p>
            <h2 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
              {gettext("The right follow-up, without losing control.")}
            </h2>
          </div>

          <div class="mt-10 space-y-8 lg:mt-14 lg:space-y-12">
            <article
              id="workflow-demo-reply"
              class="overflow-hidden rounded-2xl border border-base-content/10 bg-base-100 shadow-sm"
            >
              <div class="flex flex-col p-6 sm:p-8 lg:p-10">
                <div class="flex items-center gap-3">
                  <span class="flex size-9 items-center justify-center rounded-xl bg-primary text-sm font-bold text-primary-content">
                    01
                  </span>
                  <span class="text-sm font-semibold text-primary">
                    {gettext("AI email reply")}
                  </span>
                </div>
                <h3 class="mt-6 text-2xl font-bold tracking-tight">
                  {gettext("A customer asks about price and availability.")}
                </h3>
                <blockquote class="mt-5 border-l-2 border-primary/35 pl-4 text-sm leading-6 text-base-content/65">
                  {gettext(
                    "“What is the price? Is it currently in stock, and when could it be delivered?”"
                  )}
                </blockquote>
                <p class="mt-6 leading-7 text-base-content/65">
                  {gettext(
                    "Konevo prepares a concise English draft for review. It confirms it will check the missing details and asks which model the customer is considering."
                  )}
                </p>
                <div class="mt-auto pt-8">
                  <span class="inline-flex items-center gap-2 rounded-lg border border-primary/20 bg-primary/8 px-3 py-2 text-sm font-semibold text-primary">
                    <.icon name="icon-[tabler--file-text-ai]" class="size-4" />
                    {gettext("Review before sending")}
                  </span>
                </div>
              </div>
              <figure class="bg-base-200/50 p-3 sm:p-5">
                <img
                  src={~p"/images/automation_ai/draft.png"}
                  alt={gettext("AI email draft in Konevo")}
                  class="w-full rounded-xl border border-base-content/10 shadow-lg shadow-base-content/10"
                />
              </figure>
            </article>

            <article
              id="workflow-demo-task"
              class="overflow-hidden rounded-2xl border border-base-content/10 bg-base-100 shadow-sm"
            >
              <div class="flex flex-col p-6 sm:p-8 lg:p-10">
                <div class="flex items-center gap-3">
                  <span class="flex size-9 items-center justify-center rounded-xl bg-primary text-sm font-bold text-primary-content">
                    02
                  </span>
                  <span class="text-sm font-semibold text-primary">
                    {gettext("Email to task")}
                  </span>
                </div>
                <h3 class="mt-6 text-2xl font-bold tracking-tight">
                  {gettext("Several questions, one actionable next step.")}
                </h3>
                <blockquote class="mt-5 border-l-2 border-primary/35 pl-4 text-sm leading-6 text-base-content/65">
                  {gettext(
                    "“Please send the price, current availability, and the possible delivery time.”"
                  )}
                </blockquote>
                <p class="mt-6 leading-7 text-base-content/65">
                  {gettext(
                    "Konevo combines the related request into one task suggestion: prepare a reply about the espresso machine's price, availability, and delivery."
                  )}
                </p>
                <div class="mt-auto pt-8">
                  <span class="inline-flex items-center gap-2 rounded-lg border border-primary/20 bg-primary/8 px-3 py-2 text-sm font-semibold text-primary">
                    <.icon name="icon-[tabler--checkbox]" class="size-4" />
                    {gettext("Approve or refine the task")}
                  </span>
                </div>
              </div>
              <figure class="bg-base-200/50 p-3 sm:p-5">
                <img
                  src={~p"/images/automation_ai/task.png"}
                  alt={gettext("AI task suggestion in Konevo")}
                  class="w-full rounded-xl border border-base-content/10 shadow-lg shadow-base-content/10"
                />
              </figure>
            </article>

            <article
              id="workflow-demo-no-reply"
              class="overflow-hidden rounded-2xl border border-base-content/10 bg-base-100 shadow-sm"
            >
              <div class="flex flex-col p-6 sm:p-8 lg:p-10">
                <div class="flex items-center gap-3">
                  <span class="flex size-9 items-center justify-center rounded-xl bg-primary text-sm font-bold text-primary-content">
                    03
                  </span>
                  <span class="text-sm font-semibold text-primary">
                    {gettext("No-reply follow-up")}
                  </span>
                </div>
                <h3 class="mt-6 text-2xl font-bold tracking-tight">
                  {gettext("A timely nudge when a conversation goes quiet.")}
                </h3>
                <blockquote class="mt-5 border-l-2 border-primary/35 pl-4 text-sm leading-6 text-base-content/65">
                  {gettext(
                    "After the chosen delay, the customer has not replied to the earlier message about an espresso machine."
                  )}
                </blockquote>
                <p class="mt-6 leading-7 text-base-content/65">
                  {gettext(
                    "Konevo prepares a considerate follow-up that refers to the earlier conversation, makes no new promises, and asks one low-pressure question."
                  )}
                </p>
                <div class="mt-auto pt-8">
                  <span class="inline-flex items-center gap-2 rounded-lg border border-primary/20 bg-primary/8 px-3 py-2 text-sm font-semibold text-primary">
                    <.icon name="icon-[tabler--mail-forward]" class="size-4" />
                    {gettext("Send only when ready")}
                  </span>
                </div>
              </div>
              <figure class="bg-base-200/50 p-3 sm:p-5">
                <img
                  src={~p"/images/automation_ai/no_reply.png"}
                  alt={gettext("No-reply follow-up draft in Konevo")}
                  class="w-full rounded-xl border border-base-content/10 shadow-lg shadow-base-content/10"
                />
              </figure>
            </article>
          </div>
        </div>
      </section>

      <section
        id="workflow-demo-control"
        class="mx-auto max-w-4xl px-5 py-16 text-center sm:px-8 lg:px-10 lg:py-24"
      >
        <span class="flex size-11 mx-auto items-center justify-center rounded-xl bg-primary/10 text-primary">
          <.icon name="icon-[tabler--adjustments-horizontal]" class="size-5" />
        </span>
        <h2 class="mt-5 text-3xl font-bold tracking-tight sm:text-4xl">
          {gettext("Built around your workflow.")}
        </h2>
        <p class="mx-auto mt-4 max-w-2xl leading-7 text-base-content/65">
          {gettext("Each automation can run automatically or wait for your review.")}
        </p>
        <a href={~p"/"} class="btn btn-primary mt-7 gap-2">
          {gettext("Explore Konevo")}
          <.icon name="icon-[tabler--arrow-right]" class="size-4" />
        </a>
      </section>
    </main>
    """
  end
end
