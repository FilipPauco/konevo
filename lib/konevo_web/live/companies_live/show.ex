defmodule KonevoWeb.CompaniesLive.Show do
  use KonevoWeb, :live_view

  alias Konevo.Companies
  alias Konevo.Contacts.Contact
  alias Konevo.Deals
  alias Konevo.Tasks
  alias Konevo.Tasks.Task
  import KonevoWeb.TasksLive.Components

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:company, nil)
     |> assign(:task_timeline_tasks, [])
     |> assign(:task_form_open?, false)
     |> assign(:task_form_task, nil)
     |> assign(:contact_form_open?, false)
     |> assign(:contact_form_contact, nil)
     |> assign(:task_types, [])
     |> assign(:task_options, [])
     |> assign(:notes_editor_open?, false)
     |> assign(:notes_form, nil)
     |> stream(:contacts, [])
     |> stream_configure(:deals, dom_id: &"company-deal-#{&1.id}")
     |> stream(:deals, [])}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    if connected?(socket) do
      company = Companies.get_company_by_slug_or_id!(socket.assigns.current_scope, id)

      {:noreply, assign_company_details(socket, company)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({KonevoWeb.CompaniesLive.FormComponent, {:saved, company, _action}}, socket) do
    company = Companies.get_company!(socket.assigns.current_scope, company.id)

    {:noreply,
     socket
     |> assign_company_details(company)}
  end

  def handle_info({KonevoWeb.ContactsLive.FormComponent, {:saved, _contact, :created}}, socket) do
    company = Companies.get_company!(socket.assigns.current_scope, socket.assigns.company.id)

    {:noreply,
     socket
     |> assign(:contact_form_open?, false)
     |> assign(:contact_form_contact, nil)
     |> assign_company_details(company)
     |> put_flash(:success, gettext("Contact created"))}
  end

  def handle_info(
        {KonevoWeb.TasksLive.FormComponent, {:saved, _task, _dependency_result}},
        socket
      ) do
    company = Companies.get_company!(socket.assigns.current_scope, socket.assigns.company.id)

    {:noreply,
     socket
     |> assign(:task_form_open?, false)
     |> assign(:task_form_task, nil)
     |> assign_company_details(company)
     |> put_flash(:success, gettext("Task created"))}
  end

  @impl true
  def handle_event("edit_notes", _params, socket) do
    case Companies.authorize_company(
           socket.assigns.current_scope,
           :update,
           socket.assigns.company
         ) do
      :ok ->
        {:noreply, assign(socket, :notes_editor_open?, true)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this company"))}
    end
  end

  def handle_event("cancel_notes", _params, socket) do
    {:noreply,
     socket
     |> assign(:notes_editor_open?, false)
     |> assign(:notes_form, to_form(Companies.change_company(socket.assigns.company)))}
  end

  def handle_event("save_notes", %{"company" => params}, socket) do
    company = Companies.get_company!(socket.assigns.current_scope, socket.assigns.company.id)

    case Companies.update_company(
           socket.assigns.current_scope,
           company,
           Map.take(params, ["notes"])
         ) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:company, updated)
         |> assign(:notes_editor_open?, false)
         |> assign(:notes_form, to_form(Companies.change_company(updated)))
         |> put_flash(:success, gettext("Notes saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :notes_form, to_form(changeset, action: :validate))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this company"))}
    end
  end

  def handle_event("delete", _params, socket) do
    company = Companies.get_company!(socket.assigns.current_scope, socket.assigns.company.id)

    case Companies.delete_company(socket.assigns.current_scope, company) do
      {:ok, _company} ->
        {:noreply, push_navigate(socket, to: ~p"/companies")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot delete this company"))}
    end
  end

  def handle_event("archive", _params, socket) do
    company = Companies.get_company!(socket.assigns.current_scope, socket.assigns.company.id)

    case Companies.archive_company(socket.assigns.current_scope, company) do
      {:ok, company} ->
        {:noreply,
         socket
         |> assign(:company, company)
         |> put_flash(:success, gettext("Company archived"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot archive this company"))}
    end
  end

  def handle_event("restore", _params, socket) do
    company = Companies.get_company!(socket.assigns.current_scope, socket.assigns.company.id)

    case Companies.restore_company(socket.assigns.current_scope, company) do
      {:ok, company} ->
        {:noreply,
         socket
         |> assign(:company, company)
         |> put_flash(:success, gettext("Company restored"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot restore this company"))}
    end
  end

  def handle_event("open_new_contact", _params, socket) do
    {:noreply,
     assign(socket,
       contact_form_open?: true,
       contact_form_contact: %Contact{company_id: socket.assigns.company.id}
     )}
  end

  def handle_event("cancel_new_contact", _params, socket) do
    {:noreply, assign(socket, contact_form_open?: false, contact_form_contact: nil)}
  end

  def handle_event("open_new_task", _params, socket) do
    {:noreply,
     assign(socket,
       task_form_open?: true,
       task_form_task: new_task_for_company(socket.assigns.company)
     )}
  end

  def handle_event("cancel_new_task", _params, socket) do
    {:noreply, assign(socket, task_form_open?: false, task_form_task: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div :if={@company} class="mx-auto max-w-6xl px-4 py-5 sm:px-6 sm:py-6">
        <%!-- Page trail --%>
        <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
          <nav id="company-back-link" class="flex items-center gap-1.5 text-sm">
            <.link
              navigate={~p"/companies"}
              class="group flex items-center gap-1 text-base-content/45 transition-colors duration-150 hover:text-base-content/80"
            >
              <.icon
                name="icon-[tabler--arrow-left]"
                class="size-3.5 transition-transform duration-150 group-hover:-translate-x-0.5"
              />
              <span class="font-medium">{gettext("Companies")}</span>
            </.link>
            <.icon name="icon-[tabler--chevron-right]" class="size-3.5 text-base-content/20" />
            <span class="max-w-[180px] truncate font-medium text-base-content/70 sm:max-w-xs">
              {@company.name}
            </span>
          </nav>
          <div class="inline-flex items-center gap-2 rounded-full border border-base-content/10 bg-base-100 px-3 py-1.5 text-xs font-medium text-base-content/45 shadow-sm">
            <.icon name="icon-[tabler--building-skyscraper]" class="size-3.5" />
            {gettext("Company profile")}
          </div>
        </div>

        <%!-- Hero card --%>
        <div
          id="company-details"
          class="mb-6 overflow-hidden rounded-2xl border border-base-content/15 bg-base-100 shadow-sm"
        >
          <div
            class="h-24"
            style="background: linear-gradient(135deg, color-mix(in oklch, var(--color-primary) 20%, var(--color-base-200)), color-mix(in oklch, var(--color-primary) 8%, var(--color-base-100)))"
          />
          <div class="px-6 pb-6">
            <div class="flex flex-wrap items-end justify-between gap-4">
              <%!-- Company avatar --%>
              <div class="-mt-10 flex size-20 shrink-0 items-center justify-center rounded-2xl border-4 border-base-100 bg-primary text-3xl font-bold uppercase text-primary-content shadow-lg ring-1 ring-base-content/10">
                {String.first(@company.name)}
              </div>
              <%!-- Action buttons --%>
              <div class="flex items-center gap-2 pt-2">
                <.link
                  patch={~p"/companies/#{@company}/edit"}
                  class="btn btn-primary btn-sm gap-1.5"
                >
                  <.icon name="icon-[tabler--pencil]" class="size-3.5" />
                  {gettext("Edit")}
                </.link>
                <button
                  :if={is_nil(@company.archived_at)}
                  type="button"
                  id="archive-company"
                  phx-click="archive"
                  class="btn btn-neutral btn-sm gap-1.5"
                >
                  <.icon name="icon-[tabler--archive]" class="size-3.5" />
                  {gettext("Archive")}
                </button>
                <button
                  :if={!is_nil(@company.archived_at)}
                  type="button"
                  id="restore-company"
                  phx-click="restore"
                  class="btn btn-sm btn-outline gap-1.5 border-success/30 bg-success/10 text-success shadow-sm hover:bg-success/15"
                >
                  <.icon name="icon-[tabler--archive-off]" class="size-3.5" />
                  {gettext("Restore")}
                </button>
                <button
                  type="button"
                  id="delete-company"
                  phx-click="delete"
                  data-confirm={
                    gettext("Delete this company? Contacts will be kept without a company.")
                  }
                  class="btn btn-sm btn-error btn-danger gap-1.5 shadow-sm"
                >
                  <.icon name="icon-[tabler--trash]" class="size-3.5" />
                  {gettext("Delete")}
                </button>
              </div>
            </div>

            <div class="mt-3">
              <h1 class="text-2xl font-bold text-base-content">{@company.name}</h1>
              <div class="mt-2 flex flex-wrap items-center gap-2">
                <span
                  :if={@company.industry}
                  class="inline-flex max-w-full items-center gap-1.5 rounded-md border border-primary/15 bg-primary/8 px-2.5 py-1 text-xs font-semibold text-base-content/70 shadow-sm shadow-primary/5"
                >
                  <.icon name="icon-[tabler--category]" class="size-3.5 shrink-0 text-primary" />
                  <span class="truncate">{@company.industry}</span>
                </span>
                <span
                  :if={!is_nil(@company.archived_at)}
                  class="inline-flex items-center gap-1 rounded-md border border-warning/30 bg-warning/10 px-2.5 py-0.5 text-xs font-semibold text-warning"
                >
                  <.icon name="icon-[tabler--archive]" class="size-3.5" />
                  {gettext("Archived")}
                </span>
                <span class="inline-flex items-center gap-1 text-sm text-base-content/50">
                  <span class="icon-[tabler--users] size-3.5" />
                  {ngettext(
                    "%{count} contact",
                    "%{count} contacts",
                    length(@company.contacts),
                    count: length(@company.contacts)
                  )}
                </span>
              </div>
            </div>
          </div>
        </div>

        <%!-- Main content grid --%>
        <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <%!-- Left: details + notes --%>
          <div class="flex flex-col gap-6 lg:col-span-2">
            <%!-- Company info card --%>
            <div class="overflow-hidden rounded-2xl border border-base-content/15 bg-base-100 shadow-sm">
              <div class="border-b border-base-content/10 px-5 py-4">
                <h2 class="text-sm font-semibold text-base-content">
                  {gettext("Company Information")}
                </h2>
              </div>
              <dl class="divide-y divide-base-content/8">
                <.detail_row
                  icon="icon-[tabler--world]"
                  label={gettext("Website")}
                  value={@company.website}
                  href={@company.website}
                />
                <.detail_row
                  icon="icon-[tabler--brand-linkedin]"
                  label={gettext("LinkedIn")}
                  value={@company.linkedin_url}
                  href={@company.linkedin_url}
                />
                <.detail_row
                  icon="icon-[tabler--phone]"
                  label={gettext("Phone")}
                  value={@company.phone}
                  href={if @company.phone, do: "tel:#{@company.phone}", else: nil}
                />
                <.detail_row
                  icon="icon-[tabler--category]"
                  label={gettext("Industry")}
                  value={@company.industry}
                />
                <.detail_row
                  icon="icon-[tabler--calendar-plus]"
                  label={gettext("Created")}
                  value={Calendar.strftime(@company.inserted_at, "%B %-d, %Y")}
                />
                <.detail_row
                  icon="icon-[tabler--calendar-event]"
                  label={gettext("Last Updated")}
                  value={Calendar.strftime(@company.updated_at, "%B %-d, %Y")}
                />
              </dl>
            </div>

            <%!-- Notes card --%>
            <div class="overflow-hidden rounded-2xl border border-base-content/15 bg-base-100 shadow-sm">
              <div class="flex items-center justify-between gap-3 border-b border-base-content/10 px-5 py-4">
                <h2 class="text-sm font-semibold text-base-content">{gettext("Notes")}</h2>
                <button
                  :if={!@notes_editor_open?}
                  type="button"
                  id="edit-company-notes"
                  phx-click="edit_notes"
                  class="btn btn-primary btn-sm gap-1.5"
                  aria-label={gettext("Edit notes")}
                >
                  <.icon name="icon-[tabler--pencil]" class="size-4" />
                  {gettext("Edit")}
                </button>
              </div>
              <div :if={!@notes_editor_open?} class="px-5 py-4">
                <%= if @company.notes && @company.notes != "" do %>
                  <div class="rich-text-content text-sm leading-relaxed text-base-content/80">
                    {KonevoWeb.HTMLSanitizer.basic_html(@company.notes)}
                  </div>
                <% else %>
                  <div class="flex flex-col items-center justify-center py-8 text-center">
                    <span class="icon-[tabler--notes] mb-3 block size-8 text-base-content/20" />
                    <p class="text-sm text-base-content/40">{gettext("No notes yet.")}</p>
                    <button
                      type="button"
                      phx-click="edit_notes"
                      class="mt-2 inline-flex items-center gap-1 text-xs text-primary transition-colors hover:underline"
                    >
                      <.icon name="icon-[tabler--pencil-plus]" class="size-3.5" />
                      {gettext("Add a note")}
                    </button>
                  </div>
                <% end %>
              </div>
              <div :if={@notes_editor_open?} class="px-5 py-4">
                <.form for={@notes_form} id="company-notes-form" phx-submit="save_notes">
                  <.rich_text_input
                    field={@notes_form[:notes]}
                    placeholder={gettext("Add notes about this company...")}
                  />
                  <div class="mt-3 flex justify-end gap-2">
                    <button type="button" phx-click="cancel_notes" class="btn btn-ghost btn-sm">
                      {gettext("Cancel")}
                    </button>
                    <.button
                      class="btn btn-primary btn-sm gap-1.5"
                      phx-disable-with={gettext("Saving…")}
                    >
                      <.icon name="icon-[tabler--device-floppy]" class="size-4" />
                      {gettext("Save notes")}
                    </.button>
                  </div>
                </.form>
              </div>
            </div>
          </div>

          <%!-- Right: related sections --%>
          <div class="flex flex-col gap-6">
            <%!-- Contacts --%>
            <div class="overflow-hidden rounded-2xl border border-base-content/15 bg-base-100 shadow-sm">
              <div class="flex items-center justify-between border-b border-base-content/10 px-5 py-4">
                <h2 class="flex items-center gap-2 text-sm font-semibold text-base-content">
                  <span class="icon-[tabler--users] size-4 text-base-content/40" />
                  {gettext("Contacts")}
                </h2>
                <button
                  type="button"
                  id="company-add-contact"
                  phx-click="open_new_contact"
                  class="btn btn-primary btn-xs"
                >
                  {gettext("Add")}
                </button>
              </div>
              <div id="company-contacts" phx-update="stream" class="divide-y divide-base-content/8">
                <div
                  id="company-contacts-empty"
                  class="hidden only:block px-5 py-8 text-center text-sm text-base-content/40"
                >
                  {gettext("No contacts at this company yet.")}
                </div>
                <.link
                  :for={{id, contact} <- @streams.contacts}
                  id={id}
                  navigate={~p"/contacts/#{contact}"}
                  class="flex items-center gap-3 px-5 py-3 transition-colors hover:bg-base-200/50"
                >
                  <span class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary">
                    {String.first(contact.first_name)}{String.first(contact.last_name || "")}
                  </span>
                  <span class="min-w-0">
                    <span class="block truncate text-sm font-medium">
                      {contact.first_name} {contact.last_name}
                    </span>
                    <span class="block truncate text-xs text-base-content/45">
                      {contact.email || gettext("No email")}
                    </span>
                  </span>
                </.link>
              </div>
            </div>

            <%!-- Tasks --%>
            <div class="overflow-hidden rounded-2xl border border-base-content/15 bg-base-100 shadow-sm">
              <div class="flex items-center justify-between border-b border-base-content/10 px-5 py-4">
                <h2 class="flex items-center gap-2 text-sm font-semibold text-base-content">
                  <.icon name="icon-[tabler--checkbox]" class="size-4 text-base-content/40" />
                  {gettext("Tasks")}
                </h2>
                <button
                  type="button"
                  id="company-add-task"
                  phx-click="open_new_task"
                  class="btn btn-primary btn-xs"
                >
                  {gettext("Add")}
                </button>
              </div>
              <.task_timeline
                id="company-task-timeline"
                tasks={@task_timeline_tasks}
                empty_message={gettext("Tasks linked to this company will appear here.")}
                show_contact?={true}
              />
            </div>

            <%!-- Deals --%>
            <div
              id="company-deals-card"
              class="overflow-hidden rounded-2xl border border-base-content/15 bg-base-100 shadow-sm"
            >
              <div class="flex items-center justify-between border-b border-base-content/10 px-5 py-4">
                <h2 class="flex items-center gap-2 text-sm font-semibold text-base-content">
                  <.icon name="icon-[tabler--briefcase]" class="size-4 text-base-content/40" />
                  {gettext("Deals")}
                </h2>
                <span :if={not @deals_empty?} class="badge badge-sm badge-ghost rounded-md text-xs">
                  {gettext("Active")}
                </span>
              </div>
              <div id="company-deals" phx-update="stream" class="divide-y divide-base-content/8">
                <div
                  id="company-deals-empty"
                  class="hidden only:flex flex-col items-center justify-center px-5 py-10 text-center"
                >
                  <.icon
                    name="icon-[tabler--currency-dollar]"
                    class="mb-2 size-8 text-base-content/15"
                  />
                  <p class="text-xs leading-relaxed text-base-content/35">
                    {gettext("Deals linked to this company will appear here.")}
                  </p>
                </div>
                <.link
                  :for={{id, deal} <- @streams.deals}
                  id={id}
                  navigate={~p"/deals/#{deal}/edit"}
                  class="group flex items-center justify-between gap-3 px-5 py-3.5 transition-colors duration-150 hover:bg-base-200/60"
                >
                  <span class="min-w-0">
                    <span class="block truncate text-sm font-medium text-base-content group-hover:text-primary">
                      {deal.title}
                    </span>
                    <span class="mt-1 flex flex-wrap items-center gap-1.5 text-[11px] text-base-content/50">
                      <span
                        :if={deal.stage}
                        class="rounded-md bg-base-200 px-1.5 py-0.5 font-medium text-base-content/60"
                      >
                        {deal.stage.name}
                      </span>
                      <span :if={deal.contact} class="truncate">
                        {deal.contact.first_name} {deal.contact.last_name}
                      </span>
                    </span>
                  </span>
                  <span class="shrink-0 text-sm font-semibold tabular-nums text-base-content/75">
                    {deal_value_label(deal.value, deal.currency)}
                  </span>
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>

      <.modal
        :if={@live_action == :edit && @company}
        id="company-modal"
        show
        on_cancel={hide_modal("company-modal") |> JS.patch(~p"/companies/#{@company}")}
      >
        <.live_component
          module={KonevoWeb.CompaniesLive.FormComponent}
          id={@company.id}
          title={gettext("Edit Company")}
          action={:edit}
          company={@company}
          current_scope={@current_scope}
          patch={~p"/companies/#{@company}"}
        />
      </.modal>

      <.modal
        :if={@contact_form_open? && @contact_form_contact}
        id="company-contact-modal"
        show
        on_cancel={hide_modal("company-contact-modal") |> JS.push("cancel_new_contact")}
      >
        <.live_component
          module={KonevoWeb.ContactsLive.FormComponent}
          id="company-contact-form-component"
          title={gettext("New Contact")}
          action={:new}
          contact={@contact_form_contact}
          current_scope={@current_scope}
          cancel_event="cancel_new_contact"
        />
      </.modal>

      <.modal
        :if={@task_form_open? && @task_form_task}
        id="company-task-modal"
        show
        on_cancel={hide_modal("company-task-modal") |> JS.push("cancel_new_task")}
      >
        <.live_component
          module={KonevoWeb.TasksLive.FormComponent}
          id="company-task-form-component"
          task={@task_form_task}
          current_scope={@current_scope}
          task_types={@task_types}
          task_options={@task_options}
          parent_task_id={nil}
          cancel_event="cancel_new_task"
        />
      </.modal>
    </Layouts.app>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :href, :string, default: nil

  defp detail_row(assigns) do
    ~H"""
    <div class="flex items-center gap-4 px-5 py-3.5">
      <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-base-200">
        <span class={[@icon, "size-4 text-base-content/50"]} />
      </div>
      <div class="min-w-0 flex-1">
        <dt class="text-xs text-base-content/40">{@label}</dt>
        <dd class="mt-0.5 text-sm font-medium">
          <%= if @href do %>
            <a
              href={@href}
              target={if String.starts_with?(@href, "http"), do: "_blank", else: nil}
              rel={if String.starts_with?(@href, "http"), do: "noopener noreferrer", else: nil}
              class="text-primary transition-colors hover:underline"
            >
              {@value}
            </a>
          <% else %>
            <span class={if @value, do: "text-base-content", else: "text-base-content/30"}>
              {@value || "—"}
            </span>
          <% end %>
        </dd>
      </div>
    </div>
    """
  end

  defp assign_company_details(socket, company) do
    socket
    |> assign(:page_title, company.name)
    |> assign(:company, company)
    |> assign(:notes_editor_open?, false)
    |> assign(:notes_form, to_form(Companies.change_company(company)))
    |> assign_company_tasks(company)
    |> assign_task_form_options()
    |> assign_company_deals(company)
    |> stream(:contacts, company.contacts, reset: true)
  end

  defp assign_company_tasks(socket, company) do
    case Tasks.list_tasks_for_company(socket.assigns.current_scope, company) do
      {:ok, tasks} -> assign(socket, :task_timeline_tasks, tasks)
      {:error, _reason} -> assign(socket, :task_timeline_tasks, [])
    end
  end

  defp assign_company_deals(socket, company) do
    deals = Deals.list_deals(socket.assigns.current_scope, company_id: company.id)

    socket
    |> assign(:deals_empty?, deals == [])
    |> stream(:deals, deals, reset: true)
  end

  defp deal_value_label(value, currency) do
    "#{currency} #{Decimal.to_string(value, :normal)}"
  end

  defp assign_task_form_options(socket) do
    with {:ok, task_types} <- Tasks.list_task_types(socket.assigns.current_scope),
         {:ok, task_options} <- Tasks.list_task_options(socket.assigns.current_scope) do
      assign(socket, task_types: task_types, task_options: task_options)
    else
      _error -> assign(socket, task_types: [], task_options: [])
    end
  end

  defp new_task_for_company(company) do
    %Task{
      due_date: default_due_date(),
      company_id: company.id
    }
  end

  defp default_due_date, do: DateTime.utc_now(:second) |> DateTime.add(86_400, :second)
end
