defmodule KonevoWeb.ContactsLive.Show do
  use KonevoWeb, :live_view

  require Logger

  alias Konevo.Contacts
  alias Konevo.Deals
  alias Konevo.Tasks
  alias Konevo.Tasks.Task
  alias Konevo.Uploads
  alias Konevo.Uploads.{UploadConfig, UploadProcessor}
  import KonevoWeb.TasksLive.Components

  @avatar_context :avatar

  @impl true
  def mount(_params, _session, socket) do
    config = UploadConfig.get!(@avatar_context)

    {:ok,
     socket
     |> assign(:contact, nil)
     |> assign(:avatar, nil)
     |> assign(:task_timeline_tasks, [])
     |> assign(:task_form_open?, false)
     |> assign(:task_form_task, nil)
     |> assign(:task_types, [])
     |> assign(:task_options, [])
     |> assign(:can_update_contact?, false)
     |> assign(:notes_editor_open?, false)
     |> stream_configure(:deals, dom_id: &"contact-deal-#{&1.id}")
     |> stream(:deals, [])
     |> allow_upload(@avatar_context,
       accept: config.allowed_extensions,
       auto_upload: true,
       max_entries: config.max_entries,
       max_file_size: config.max_file_size,
       progress: &handle_avatar_progress/3
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    if connected?(socket) do
      contact = Contacts.get_contact_by_slug_or_id!(socket.assigns.current_scope, id)

      {:noreply,
       socket
       |> assign(:page_title, "#{contact.first_name} #{contact.last_name}")
       |> assign(:contact, contact)
       |> assign(:can_update_contact?, contact_update_allowed?(socket, contact))
       |> assign(:notes_editor_open?, false)
       |> assign_avatar(contact)
       |> assign_contact_tasks(contact)
       |> assign_contact_deals(contact)
       |> assign_task_form_options()
       |> assign_notes_form(contact)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({KonevoWeb.ContactsLive.FormComponent, {:saved, contact, _action}}, socket) do
    contact = Contacts.get_contact!(socket.assigns.current_scope, contact.id)

    {:noreply,
     socket
     |> assign(:contact, contact)
     |> assign_avatar(contact)
     |> assign_contact_tasks(contact)
     |> assign_contact_deals(contact)
     |> push_patch(to: ~p"/contacts/#{contact}")}
  end

  def handle_info(
        {KonevoWeb.TasksLive.FormComponent, {:saved, _task, _dependency_result}},
        socket
      ) do
    contact = Contacts.get_contact!(socket.assigns.current_scope, socket.assigns.contact.id)

    {:noreply,
     socket
     |> assign(:task_form_open?, false)
     |> assign(:task_form_task, nil)
     |> assign(:contact, contact)
     |> assign_contact_tasks(contact)
     |> assign_task_form_options()
     |> put_flash(:success, gettext("Task created"))}
  end

  @impl true
  def handle_event("validate_avatar", _params, socket) do
    case authorize_contact_update(socket) do
      {:ok, _contact} ->
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this contact"))}
    end
  end

  def handle_event("cancel_avatar", %{"ref" => ref}, socket) do
    case authorize_contact_update(socket) do
      {:ok, _contact} ->
        {:noreply, cancel_upload(socket, @avatar_context, ref)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this contact"))}
    end
  end

  @impl true
  def handle_event("delete", _, socket) do
    contact = socket.assigns.contact
    {:ok, _} = Contacts.delete_contact(socket.assigns.current_scope, contact)
    {:noreply, push_navigate(socket, to: ~p"/contacts")}
  end

  def handle_event("archive", _, socket) do
    contact = Contacts.get_contact!(socket.assigns.current_scope, socket.assigns.contact.id)

    case Contacts.archive_contact(socket.assigns.current_scope, contact) do
      {:ok, contact} ->
        {:noreply,
         socket
         |> assign(:contact, contact)
         |> put_flash(:success, gettext("Contact archived"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot archive this contact"))}
    end
  end

  def handle_event("restore", _, socket) do
    contact = Contacts.get_contact!(socket.assigns.current_scope, socket.assigns.contact.id)

    case Contacts.restore_contact(socket.assigns.current_scope, contact) do
      {:ok, contact} ->
        {:noreply,
         socket
         |> assign(:contact, contact)
         |> put_flash(:success, gettext("Contact restored"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot restore this contact"))}
    end
  end

  def handle_event("edit_notes", _params, socket) do
    {:noreply, assign(socket, :notes_editor_open?, true)}
  end

  def handle_event("cancel_notes", _params, socket) do
    {:noreply,
     socket
     |> assign(:notes_editor_open?, false)
     |> assign_notes_form(socket.assigns.contact)}
  end

  def handle_event("save_notes", %{"contact" => contact_params}, socket) do
    contact = Contacts.get_contact!(socket.assigns.current_scope, socket.assigns.contact.id)

    case Contacts.update_contact(socket.assigns.current_scope, contact, contact_params) do
      {:ok, contact} ->
        {:noreply,
         socket
         |> put_flash(:success, gettext("Notes saved"))
         |> assign(:contact, contact)
         |> assign(:notes_editor_open?, false)
         |> assign_notes_form(contact)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :notes_form, to_form(changeset, action: :validate))}
    end
  end

  def handle_event("save_notes", _params, socket) do
    {:noreply, put_flash(socket, :error, gettext("Could not save notes. Please try again"))}
  end

  def handle_event("open_new_task", _params, socket) do
    contact = socket.assigns.contact

    {:noreply,
     assign(socket,
       task_form_open?: true,
       task_form_task: new_task_for_contact(contact)
     )}
  end

  def handle_event("cancel_new_task", _params, socket) do
    {:noreply, assign(socket, task_form_open?: false, task_form_task: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div :if={@contact} class="mx-auto max-w-6xl px-4 py-6 sm:px-6">
        <%!-- Page trail --%>
        <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
          <nav id="contact-back-link" class="flex items-center gap-1.5 text-sm">
            <.link
              navigate={~p"/contacts"}
              class="group flex items-center gap-1 text-base-content/45 transition-colors duration-150 hover:text-base-content/80"
            >
              <.icon
                name="icon-[tabler--arrow-left]"
                class="size-3.5 transition-transform duration-150 group-hover:-translate-x-0.5"
              />
              <span class="font-medium">{gettext("Contacts")}</span>
            </.link>
            <.icon name="icon-[tabler--chevron-right]" class="size-3.5 text-base-content/20" />
            <span class="max-w-[180px] truncate font-medium text-base-content/70 sm:max-w-xs">
              {@contact.first_name} {@contact.last_name}
            </span>
          </nav>
          <div class="inline-flex items-center gap-2 rounded-full border border-base-content/10 bg-base-100 px-3 py-1.5 text-xs font-medium text-base-content/45 shadow-sm">
            <.icon name="icon-[tabler--user]" class="size-3.5" />
            {gettext("Contact profile")}
          </div>
        </div>

        <%!-- Profile hero card --%>
        <div class="mb-6 overflow-hidden rounded-2xl border border-base-content/15 bg-base-100 shadow-sm">
          <div
            class="h-24"
            style="background: linear-gradient(135deg, color-mix(in oklch, var(--color-primary) 20%, var(--color-base-200)), color-mix(in oklch, var(--color-primary) 8%, var(--color-base-100)))"
          />
          <div class="px-6 pb-6">
            <div class="flex flex-wrap items-end justify-between gap-4">
              <%!-- Avatar --%>
              <% avatar_entry = List.first(@uploads.avatar.entries) %>
              <form
                :if={@can_update_contact?}
                id="contact-avatar-form"
                phx-change="validate_avatar"
                class="-mt-10"
              >
                <div class="flex flex-wrap items-end gap-3">
                  <label
                    id="contact-avatar-picker"
                    class="group relative block size-20 shrink-0 cursor-pointer overflow-hidden rounded-2xl border-4 border-base-100 bg-primary shadow-lg ring-1 ring-base-content/10 transition-all hover:-translate-y-0.5 hover:shadow-xl focus-within:ring-2 focus-within:ring-primary"
                    aria-label={gettext("Choose contact profile picture")}
                  >
                    <%= cond do %>
                      <% avatar_entry -> %>
                        <.live_img_preview
                          entry={avatar_entry}
                          class="size-full object-cover"
                        />
                      <% @avatar -> %>
                        <img
                          id="contact-avatar-image"
                          src={~p"/uploads/avatar/#{@avatar.id}"}
                          alt={gettext("Profile picture for %{name}", name: @contact.first_name)}
                          class="size-full object-cover"
                        />
                      <% true -> %>
                        <span class="flex size-full items-center justify-center text-2xl font-bold text-primary-content">
                          {String.first(@contact.first_name || "?")}
                        </span>
                    <% end %>

                    <span class="absolute inset-0 flex items-center justify-center bg-neutral/0 text-white opacity-0 transition-all group-hover:bg-neutral/45 group-hover:opacity-100">
                      <.icon name="icon-[tabler--camera]" class="size-5" />
                    </span>
                    <.live_file_input upload={@uploads.avatar} class="sr-only" />
                  </label>

                  <div :if={avatar_entry} id="contact-avatar-actions" class="mb-1 min-w-48">
                    <p class="max-w-48 truncate text-xs font-medium text-base-content/70">
                      {avatar_entry.client_name}
                    </p>
                    <p class="mt-0.5 text-xs text-base-content/40">
                      <%= if avatar_entry.done? do %>
                        {gettext("Processing image…")}
                      <% else %>
                        {gettext("Uploading… %{progress}%", progress: avatar_entry.progress)}
                      <% end %>
                    </p>
                    <progress
                      class="progress progress-primary mt-1 h-1.5 w-48"
                      value={avatar_entry.progress}
                      max="100"
                    />
                    <p
                      :for={error <- upload_errors(@uploads.avatar, avatar_entry)}
                      class="mt-1 text-xs font-medium text-error"
                    >
                      {avatar_upload_error(error)}
                    </p>
                    <div class="mt-2 flex items-center gap-2">
                      <button
                        type="button"
                        phx-click="cancel_avatar"
                        phx-value-ref={avatar_entry.ref}
                        class="btn btn-ghost btn-xs"
                      >
                        {gettext("Cancel")}
                      </button>
                    </div>
                  </div>
                </div>
              </form>
              <div
                :if={!@can_update_contact?}
                id="contact-avatar-static"
                class="-mt-10 size-20 shrink-0 overflow-hidden rounded-2xl border-4 border-base-100 bg-primary shadow-lg ring-1 ring-base-content/10"
              >
                <%= if @avatar do %>
                  <img
                    id="contact-avatar-image"
                    src={~p"/uploads/avatar/#{@avatar.id}"}
                    alt={gettext("Profile picture for %{name}", name: @contact.first_name)}
                    class="size-full object-cover"
                  />
                <% else %>
                  <span class="flex size-full items-center justify-center text-2xl font-bold text-primary-content">
                    {String.first(@contact.first_name || "?")}
                  </span>
                <% end %>
              </div>
              <%!-- Action buttons --%>
              <div class="flex items-center gap-2 pt-2">
                <.link
                  patch={~p"/contacts/#{@contact}/edit"}
                  class="btn btn-primary btn-sm gap-1.5"
                >
                  <.icon name="icon-[tabler--pencil]" class="size-3.5" />
                  {gettext("Edit")}
                </.link>
                <button
                  :if={is_nil(@contact.archived_at)}
                  type="button"
                  phx-click="archive"
                  class="btn btn-neutral btn-sm gap-1.5"
                >
                  <.icon name="icon-[tabler--archive]" class="size-3.5" />
                  {gettext("Archive")}
                </button>
                <button
                  :if={!is_nil(@contact.archived_at)}
                  type="button"
                  phx-click="restore"
                  class="btn btn-sm btn-outline gap-1.5 border-success/30 bg-success/10 text-success shadow-sm hover:bg-success/15"
                >
                  <.icon name="icon-[tabler--archive-off]" class="size-3.5" />
                  {gettext("Restore")}
                </button>
                <button
                  type="button"
                  phx-click="delete"
                  data-confirm={gettext("Delete this contact? This cannot be undone.")}
                  class="btn btn-sm btn-error btn-danger gap-1.5 shadow-sm"
                >
                  <.icon name="icon-[tabler--trash]" class="size-3.5" />
                  {gettext("Delete")}
                </button>
              </div>
            </div>

            <div class="mt-3">
              <h1 class="text-2xl font-bold text-base-content">
                {@contact.first_name} {@contact.last_name}
              </h1>
              <div class="mt-2 flex flex-wrap items-center gap-2">
                <span class={[
                  "inline-flex items-center gap-1.5 rounded-md border px-2.5 py-0.5 text-xs font-semibold",
                  status_pill_class(@contact.status)
                ]}>
                  <span class="size-1.5 shrink-0 rounded-full bg-current" />
                  {Phoenix.Naming.humanize(@contact.status)}
                </span>
                <span
                  :if={!is_nil(@contact.archived_at)}
                  class="inline-flex items-center gap-1 rounded-md border border-warning/30 bg-warning/10 px-2.5 py-0.5 text-xs font-semibold text-warning"
                >
                  <.icon name="icon-[tabler--archive]" class="size-3.5" />
                  {gettext("Archived")}
                </span>
                <.link
                  :if={@contact.company}
                  navigate={~p"/companies/#{@contact.company}"}
                  class="inline-flex items-center gap-1 text-sm text-base-content/55 transition-colors hover:text-primary"
                >
                  <span class="icon-[tabler--building] size-3.5" />
                  {@contact.company.name}
                </.link>
                <span :if={!@contact.company} class="text-sm text-base-content/30">
                  {gettext("No company")}
                </span>
              </div>
            </div>
          </div>
        </div>

        <%!-- Main content grid --%>
        <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <%!-- Left: details + notes --%>
          <div class="flex flex-col gap-6 lg:col-span-2">
            <%!-- Contact info card --%>
            <div class="overflow-hidden rounded-2xl border border-base-content/15 bg-base-100 shadow-sm">
              <div class="border-b border-base-content/10 px-5 py-4">
                <h2 class="text-sm font-semibold text-base-content">
                  {gettext("Contact Information")}
                </h2>
              </div>
              <dl class="divide-y divide-base-content/8">
                <%!-- Email --%>
                <div class="flex items-center gap-4 px-5 py-3.5">
                  <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-base-200">
                    <span class="icon-[tabler--mail] size-4 text-base-content/50" />
                  </div>
                  <div class="min-w-0 flex-1">
                    <dt class="text-xs text-base-content/40">{gettext("Email")}</dt>
                    <dd class="mt-0.5 text-sm font-medium">
                      <%= if @contact.email do %>
                        <a
                          href={"mailto:#{@contact.email}"}
                          class="text-primary transition-colors hover:underline"
                        >
                          {@contact.email}
                        </a>
                      <% else %>
                        <span class="text-base-content/30">&mdash;</span>
                      <% end %>
                    </dd>
                  </div>
                </div>
                <%!-- Phone --%>
                <div class="flex items-center gap-4 px-5 py-3.5">
                  <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-base-200">
                    <span class="icon-[tabler--phone] size-4 text-base-content/50" />
                  </div>
                  <div class="min-w-0 flex-1">
                    <dt class="text-xs text-base-content/40">{gettext("Phone")}</dt>
                    <dd class="mt-0.5 text-sm font-medium">
                      <%= if @contact.phone do %>
                        <a
                          href={"tel:#{@contact.phone}"}
                          class="text-primary transition-colors hover:underline"
                        >
                          {@contact.phone}
                        </a>
                      <% else %>
                        <span class="text-base-content/30">-</span>
                      <% end %>
                    </dd>
                  </div>
                </div>
                <%!-- LinkedIn --%>
                <div class="flex items-center gap-4 px-5 py-3.5">
                  <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-base-200">
                    <.icon name="icon-[tabler--brand-linkedin]" class="size-4 text-base-content/50" />
                  </div>
                  <div class="min-w-0 flex-1">
                    <dt class="text-xs text-base-content/40">{gettext("LinkedIn")}</dt>
                    <dd class="mt-0.5 text-sm font-medium">
                      <%= if @contact.linkedin_url do %>
                        <a
                          href={@contact.linkedin_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="text-primary transition-colors hover:underline"
                        >
                          {@contact.linkedin_url}
                        </a>
                      <% else %>
                        <span class="text-base-content/30">—</span>
                      <% end %>
                    </dd>
                  </div>
                </div>
                <%!-- Company --%>
                <div class="flex items-center gap-4 px-5 py-3.5">
                  <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-base-200">
                    <span class="icon-[tabler--building] size-4 text-base-content/50" />
                  </div>
                  <div class="min-w-0 flex-1">
                    <dt class="text-xs text-base-content/40">{gettext("Company")}</dt>
                    <dd class="mt-0.5 text-sm font-medium">
                      <%= if @contact.company do %>
                        <.link
                          navigate={~p"/companies/#{@contact.company}"}
                          class="text-primary transition-colors hover:underline"
                        >
                          {@contact.company.name}
                        </.link>
                      <% else %>
                        <span class="text-base-content/30">—</span>
                      <% end %>
                    </dd>
                  </div>
                </div>
                <%!-- Status --%>
                <div class="flex items-center gap-4 px-5 py-3.5">
                  <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-base-200">
                    <span class="icon-[tabler--tag] size-4 text-base-content/50" />
                  </div>
                  <div class="min-w-0 flex-1">
                    <dt class="text-xs text-base-content/40">{gettext("Status")}</dt>
                    <dd class="mt-0.5">
                      <span class={[
                        "inline-flex items-center gap-1.5 rounded-md border px-2.5 py-0.5 text-xs font-semibold",
                        status_pill_class(@contact.status)
                      ]}>
                        <span class="size-1.5 shrink-0 rounded-full bg-current" />
                        {Phoenix.Naming.humanize(@contact.status)}
                      </span>
                    </dd>
                  </div>
                </div>
                <%!-- Created --%>
                <div class="flex items-center gap-4 px-5 py-3.5">
                  <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-base-200">
                    <span class="icon-[tabler--calendar-plus] size-4 text-base-content/50" />
                  </div>
                  <div class="min-w-0 flex-1">
                    <dt class="text-xs text-base-content/40">{gettext("Created")}</dt>
                    <dd class="mt-0.5 text-sm font-medium text-base-content">
                      {Calendar.strftime(@contact.inserted_at, "%B %-d, %Y")}
                    </dd>
                  </div>
                </div>
                <%!-- Last updated --%>
                <div class="flex items-center gap-4 px-5 py-3.5">
                  <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-base-200">
                    <span class="icon-[tabler--calendar-event] size-4 text-base-content/50" />
                  </div>
                  <div class="min-w-0 flex-1">
                    <dt class="text-xs text-base-content/40">{gettext("Last Updated")}</dt>
                    <dd class="mt-0.5 text-sm font-medium text-base-content">
                      {Calendar.strftime(@contact.updated_at, "%B %-d, %Y")}
                    </dd>
                  </div>
                </div>
              </dl>
            </div>

            <%!-- Notes card --%>
            <div class="overflow-hidden rounded-2xl border border-base-content/15 bg-base-100 shadow-sm">
              <div class="flex items-center justify-between gap-3 border-b border-base-content/10 px-5 py-4">
                <h2 class="text-sm font-semibold text-base-content">{gettext("Notes")}</h2>
                <button
                  :if={!@notes_editor_open?}
                  type="button"
                  phx-click="edit_notes"
                  class="btn btn-primary btn-sm gap-1.5"
                  aria-label={gettext("Edit notes")}
                >
                  <.icon name="icon-[tabler--pencil]" class="size-4" />
                  {gettext("Edit")}
                </button>
              </div>
              <div :if={!@notes_editor_open?} class="px-5 py-4">
                <%= if @contact.notes && @contact.notes != "" do %>
                  <div class="rich-text-content text-sm leading-relaxed text-base-content/80">
                    {KonevoWeb.HTMLSanitizer.basic_html(@contact.notes)}
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
                <.form
                  for={@notes_form}
                  id="contact-notes-form"
                  phx-submit="save_notes"
                  data-unsaved-form
                >
                  <.rich_text_input
                    field={@notes_form[:notes]}
                    placeholder={gettext("Add any notes about this contact…")}
                  />
                  <div class="mt-3 flex justify-end gap-2">
                    <button
                      type="button"
                      phx-click="cancel_notes"
                      data-unsaved-confirm
                      class="btn btn-ghost btn-sm"
                    >
                      {gettext("Cancel")}
                    </button>
                    <.button
                      phx-disable-with={gettext("Saving…")}
                      class="btn btn-primary btn-sm gap-1.5"
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
            <%!-- Tasks --%>
            <div class="overflow-hidden rounded-2xl border border-base-content/15 bg-base-100 shadow-sm">
              <div class="flex items-center justify-between border-b border-base-content/10 px-5 py-4">
                <h2 class="flex items-center gap-2 text-sm font-semibold text-base-content">
                  <.icon name="icon-[tabler--checkbox]" class="size-4 text-base-content/40" />
                  {gettext("Tasks")}
                </h2>
                <button
                  type="button"
                  id="contact-add-task"
                  phx-click="open_new_task"
                  class="btn btn-primary btn-xs"
                >
                  {gettext("Add")}
                </button>
              </div>
              <.task_timeline
                id="contact-task-timeline"
                tasks={@task_timeline_tasks}
                empty_message={gettext("Open tasks for this contact will appear here.")}
              />
            </div>

            <%!-- Deals --%>
            <div class="overflow-hidden rounded-2xl border border-base-content/15 bg-base-100 shadow-sm">
              <div class="flex items-center justify-between border-b border-base-content/10 px-5 py-4">
                <h2 class="flex items-center gap-2 text-sm font-semibold text-base-content">
                  <.icon name="icon-[tabler--briefcase]" class="size-4 text-base-content/40" />
                  {gettext("Deals")}
                </h2>
                <span :if={not @deals_empty?} class="badge badge-sm badge-ghost rounded-md text-xs">
                  {gettext("Active")}
                </span>
              </div>
              <div id="contact-deals" phx-update="stream" class="divide-y divide-base-content/8">
                <div
                  id="contact-deals-empty"
                  class="hidden only:flex flex-col items-center justify-center px-5 py-10 text-center"
                >
                  <.icon
                    name="icon-[tabler--currency-dollar]"
                    class="mb-2 size-8 text-base-content/15"
                  />
                  <p class="text-xs leading-relaxed text-base-content/35">
                    {gettext("Deals linked to this contact will appear here.")}
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
                    <span
                      :if={deal.stage}
                      class="mt-1 inline-flex rounded-md bg-base-200 px-1.5 py-0.5 text-[11px] font-medium text-base-content/60"
                    >
                      {deal.stage.name}
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
        :if={@live_action == :edit && @contact}
        id="contact-modal"
        show
        on_cancel={hide_modal("contact-modal") |> JS.patch(~p"/contacts/#{@contact}")}
      >
        <.live_component
          module={KonevoWeb.ContactsLive.FormComponent}
          id={@contact.id}
          title={gettext("Edit Contact")}
          action={:edit}
          contact={@contact}
          current_scope={@current_scope}
          patch={~p"/contacts/#{@contact}"}
        />
      </.modal>

      <.modal
        :if={@task_form_open? && @task_form_task}
        id="contact-task-modal"
        show
        on_cancel={hide_modal("contact-task-modal") |> JS.push("cancel_new_task")}
      >
        <.live_component
          module={KonevoWeb.TasksLive.FormComponent}
          id="contact-task-form-component"
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

  defp authorize_contact_update(socket) do
    scope = socket.assigns.current_scope
    contact = Contacts.get_contact!(scope, socket.assigns.contact.id)

    case Contacts.authorize_contact(scope, :update, contact) do
      :ok -> {:ok, contact}
      {:error, :unauthorized} -> {:error, :unauthorized}
    end
  end

  defp contact_update_allowed?(socket, contact) do
    Contacts.authorize_contact(socket.assigns.current_scope, :update, contact) == :ok
  end

  defp handle_avatar_progress(@avatar_context, entry, socket) do
    if entry.done? do
      case authorize_contact_update(socket) do
        {:ok, contact} ->
          save_avatar(socket, contact, entry)

        {:error, :unauthorized} ->
          {:noreply,
           socket
           |> cancel_upload(@avatar_context, entry.ref)
           |> put_flash(:error, gettext("You cannot update this contact"))}
      end
    else
      {:noreply, socket}
    end
  end

  defp save_avatar(socket, contact, entry) do
    scope = socket.assigns.current_scope
    tenant_id = to_string(scope.org.id)
    owner_id = to_string(contact.id)

    result =
      consume_uploaded_entry(socket, entry, fn %{path: temp_path} ->
        {:ok,
         UploadProcessor.process(
           temp_path,
           @avatar_context,
           tenant_id,
           owner_id,
           "contact",
           entry.client_name
         )}
      end)

    case result do
      {:ok, avatar} ->
        {:noreply,
         socket
         |> assign(:avatar, avatar)
         |> put_flash(:success, gettext("Profile picture updated"))}

      {:error, reason} ->
        Logger.warning("[ContactsLive.Show] Avatar upload failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, avatar_processing_error(reason))}
    end
  end

  defp assign_avatar(socket, contact) do
    case Uploads.get_latest_avatar(
           socket.assigns.current_scope,
           "contact",
           to_string(contact.id)
         ) do
      {:ok, avatar} -> assign(socket, :avatar, avatar)
      {:error, :unauthorized} -> assign(socket, :avatar, nil)
    end
  end

  defp avatar_upload_error(:too_large), do: gettext("Image is larger than 5 MB.")
  defp avatar_upload_error(:not_accepted), do: gettext("Choose a JPG, PNG, GIF or WebP image.")
  defp avatar_upload_error(:too_many_files), do: gettext("Choose one image only.")
  defp avatar_upload_error(_error), do: gettext("Could not upload this image.")

  defp avatar_processing_error({:extension_not_allowed, _extension}),
    do: gettext("Choose a JPG, PNG, GIF or WebP image")

  defp avatar_processing_error({:file_too_large, _size, _max}),
    do: gettext("Image is larger than 5 MB")

  defp avatar_processing_error({:content_type_not_allowed, _type}),
    do: gettext("The selected file is not a supported image")

  defp avatar_processing_error(_reason),
    do: gettext("Profile picture could not be saved. Please try again")

  defp assign_notes_form(socket, contact) do
    assign(socket, :notes_form, to_form(Contacts.change_contact(contact)))
  end

  defp assign_contact_tasks(socket, contact) do
    case Tasks.list_tasks_for_contact(socket.assigns.current_scope, contact) do
      {:ok, tasks} -> assign(socket, :task_timeline_tasks, tasks)
      {:error, _reason} -> assign(socket, :task_timeline_tasks, [])
    end
  end

  defp assign_contact_deals(socket, contact) do
    deals = Deals.list_deals(socket.assigns.current_scope, contact_id: contact.id)

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

  defp new_task_for_contact(contact) do
    %Task{
      due_date: default_due_date(),
      contact_id: contact.id,
      company_id: contact.company_id
    }
  end

  defp default_due_date, do: DateTime.utc_now(:second) |> DateTime.add(86_400, :second)
end
