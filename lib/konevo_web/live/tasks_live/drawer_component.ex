defmodule KonevoWeb.TasksLive.DrawerComponent do
  use KonevoWeb, :live_component

  require Logger

  alias Konevo.Tasks
  alias Konevo.Uploads
  alias Konevo.Uploads.UploadConfig
  alias Konevo.Uploads.UploadProcessor
  alias Phoenix.LiveView.AsyncResult

  @impl true
  def mount(socket) do
    config = UploadConfig.get!(:mixed_attachment)

    socket =
      allow_upload(socket, :task_attachment,
        accept:
          ~w(.pdf .doc .docx .xls .xlsx .csv .ppt .pptx .jpg .jpeg .png .gif .webp .mp4 .webm .mov),
        auto_upload: true,
        max_entries: config.max_entries,
        max_file_size: config.max_file_size,
        progress: &handle_task_attachment_progress/3
      )

    {:ok, assign(socket, :task_data, AsyncResult.loading())}
  end

  @impl true
  def update(%{task_id: task_id, open: open, refresh: refresh} = assigns, socket) do
    assigns = Map.put_new(assigns, :return_to, ~p"/tasks")
    prev_refresh = socket.assigns[:refresh]
    prev_task_id = socket.assigns[:task_id]

    socket =
      socket
      |> assign(assigns)
      |> maybe_reset_task_data(open, task_id, prev_task_id)
      |> maybe_load_task_data(assigns, task_id, prev_task_id, prev_refresh, refresh)

    {:ok, socket}
  end

  defp maybe_reset_task_data(socket, true, task_id, prev_task_id)
       when not is_nil(task_id) and prev_task_id != task_id do
    assign(socket, :task_data, AsyncResult.loading())
  end

  defp maybe_reset_task_data(socket, _open, _task_id, _prev_task_id), do: socket

  defp maybe_load_task_data(
         socket,
         %{open: true} = assigns,
         task_id,
         prev_task_id,
         prev_refresh,
         refresh
       )
       when is_nil(prev_task_id) or prev_task_id != task_id or prev_refresh != refresh do
    scope = assigns.current_scope

    assign_async(socket, :task_data, fn ->
      task = Tasks.get_task!(scope, task_id)

      {:ok,
       %{
         task_data: %{
           task: task,
           form: to_form(Tasks.change_task(task), as: :task),
           attachments: list_task_attachments(scope, task.id),
           source_attachments: list_source_attachments(scope, task.source_email_id)
         }
       }}
    end)
  end

  defp maybe_load_task_data(socket, _assigns, _task_id, _prev_task_id, _prev_refresh, _refresh),
    do: socket

  defp list_task_attachments(scope, task_id) do
    case Uploads.list_task_attachments(scope, task_id) do
      {:ok, files} -> files
      _ -> []
    end
  end

  defp list_source_attachments(_scope, nil), do: []

  defp list_source_attachments(scope, source_email_id) do
    case Uploads.list_email_attachments(scope, source_email_id) do
      {:ok, files} -> files
      _ -> []
    end
  end

  @impl true
  def handle_event("save_description", %{"task" => task_params}, socket) do
    with true <- socket.assigns.task_data.ok?,
         task <- socket.assigns.task_data.result.task,
         scope <- socket.assigns.current_scope,
         {:ok, updated_task} <-
           Tasks.update_task(scope, task, %{description: task_params["description"]}) do
      send(self(), {__MODULE__, {:updated, :description}})

      updated_task = Tasks.get_task!(scope, updated_task.id)
      new_form = to_form(Tasks.change_task(updated_task), as: :task)
      new_result = %{socket.assigns.task_data.result | task: updated_task, form: new_form}

      {:noreply,
       socket
       |> assign(:task_data, AsyncResult.ok(new_result))
       |> push_event("tiptap:clean", %{id: "task-description-#{updated_task.id}"})}
    else
      false ->
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this task"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save notes"))}
    end
  end

  def handle_event("update_status", %{"id" => _id, "status" => status}, socket) do
    with true <- socket.assigns.task_data.ok?,
         task <- socket.assigns.task_data.result.task,
         scope <- socket.assigns.current_scope,
         {:ok, updated_task} <- Tasks.update_task(scope, task, %{status: status}) do
      send(self(), {__MODULE__, {:updated, :status}})

      updated_task = Tasks.get_task!(scope, updated_task.id)
      new_result = %{socket.assigns.task_data.result | task: updated_task}
      {:noreply, assign(socket, :task_data, AsyncResult.ok(new_result))}
    else
      false ->
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this task"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, task_rule_error(reason))}
    end
  end

  def handle_event("update_priority", %{"id" => _id, "priority" => priority}, socket) do
    with true <- socket.assigns.task_data.ok?,
         task <- socket.assigns.task_data.result.task,
         scope <- socket.assigns.current_scope,
         {:ok, updated_task} <- Tasks.update_task(scope, task, %{priority: priority}) do
      send(self(), {__MODULE__, {:updated, :priority}})

      updated_task = Tasks.get_task!(scope, updated_task.id)
      new_result = %{socket.assigns.task_data.result | task: updated_task}
      {:noreply, assign(socket, :task_data, AsyncResult.ok(new_result))}
    else
      false ->
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this task"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to update priority"))}
    end
  end

  def handle_event("update_due_date", %{"task" => %{"due_date" => due_date}}, socket) do
    with true <- socket.assigns.task_data.ok?,
         task <- socket.assigns.task_data.result.task,
         scope <- socket.assigns.current_scope,
         {:ok, updated_task} <- Tasks.update_task(scope, task, %{due_date: due_date}) do
      send(self(), {__MODULE__, {:updated, :due_date}})

      updated_task = Tasks.get_task!(scope, updated_task.id)
      new_form = to_form(Tasks.change_task(updated_task), as: :task)
      new_result = %{socket.assigns.task_data.result | task: updated_task, form: new_form}

      {:noreply, assign(socket, :task_data, AsyncResult.ok(new_result))}
    else
      false ->
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this task"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to update due date"))}
    end
  end

  def handle_event("update_due_date", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_attachment", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload_attachment", _params, socket) do
    if socket.assigns.task_data.ok? do
      {:noreply, upload_task_attachments(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_attachment", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :task_attachment, ref)}
  end

  def handle_event("delete_attachment", %{"id" => id}, socket) do
    with {file_id, ""} <- Integer.parse(id),
         scope <- socket.assigns.current_scope,
         {:ok, _} <- Uploads.delete_task_attachment(scope, file_id) do
      new_attachments =
        Enum.reject(socket.assigns.task_data.result.attachments, &(to_string(&1.id) == id))

      new_result = %{socket.assigns.task_data.result | attachments: new_attachments}
      {:noreply, assign(socket, :task_data, AsyncResult.ok(new_result))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete file"))}
    end
  end

  def handle_event("delete_attachment", _params, socket) do
    {:noreply, put_flash(socket, :error, gettext("Could not delete file"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id <> "-wrapper"} class="contents">
      <%!-- Backdrop --%>
      <div
        id="task-drawer-backdrop"
        aria-hidden="true"
        data-unsaved-confirm
        phx-click={
          JS.remove_attribute("data-pre-open", to: "#task-drawer")
          |> JS.remove_attribute("data-pre-open", to: "#task-drawer-backdrop")
          |> JS.patch(@return_to)
        }
        class={[
          "fixed inset-0 z-40 bg-black/30 backdrop-blur-[2px]",
          "transition-opacity duration-300 ease-out",
          if(@open, do: "opacity-100 pointer-events-auto", else: "opacity-0 pointer-events-none")
        ]}
      /> <%!-- Drawer panel --%>
      <div
        id="task-drawer"
        phx-window-keydown={
          if(@open,
            do:
              JS.remove_attribute("data-pre-open", to: "#task-drawer")
              |> JS.remove_attribute("data-pre-open", to: "#task-drawer-backdrop")
              |> JS.patch(@return_to)
          )
        }
        phx-key="Escape"
        class={[
          "fixed inset-y-0 right-0 z-50 flex w-full max-w-2xl flex-col bg-base-100",
          "border-l border-base-content/10 drawer-panel",
          if(@open,
            do: "translate-x-0 shadow-2xl shadow-base-content/20 drawer-open",
            else: "translate-x-full drawer-closed"
          )
        ]}
        role="dialog"
        aria-modal={@open}
      >
        <div
          id="task-drawer-body"
          phx-hook="DrawerBody"
          data-task-id={@task_id}
          data-loading={if not @task_data.ok?, do: "true"}
          class="flex min-h-0 flex-1 flex-col overflow-hidden"
        >
          <%!-- Skeleton layer --%>
          <div class="drawer-skeleton flex min-h-0 flex-1 flex-col overflow-hidden">
            <div class="flex shrink-0 items-start gap-3 border-b border-base-content/10 px-5 py-4">
              <div class="skeleton mt-0.5 size-8 shrink-0 rounded-lg" />
              <div class="flex-1 space-y-2 pt-0.5">
                <div class="skeleton h-4 w-3/5 rounded" /> <div class="skeleton h-3 w-1/4 rounded" />
              </div>

              <.link
                patch={@return_to}
                phx-click={
                  JS.remove_attribute("data-pre-open", to: "#task-drawer")
                  |> JS.remove_attribute("data-pre-open", to: "#task-drawer-backdrop")
                }
                class="flex size-8 shrink-0 items-center justify-center rounded-lg text-base-content/40 transition-colors hover:bg-base-content/10 hover:text-base-content"
              >
                <.icon name="icon-[tabler--x]" class="size-5" />
              </.link>
            </div>

            <div class="min-h-0 flex-1 overflow-y-auto px-5 py-5">
              <div class="space-y-5">
                <div class="grid grid-cols-4 gap-4">
                  <div :for={_ <- 1..4} class="space-y-2">
                    <div class="skeleton h-3 w-12 rounded" />
                    <div class="skeleton h-7 w-20 rounded-full" />
                  </div>
                </div>

                <div class="space-y-2 pt-4">
                  <div class="skeleton h-4 w-24 rounded" />
                  <div class="skeleton h-44 w-full rounded-lg" />
                </div>

                <div class="space-y-2 pt-2">
                  <div class="skeleton h-4 w-20 rounded" />
                  <div class="skeleton h-28 w-full rounded-xl" />
                </div>
              </div>
            </div>
          </div>
          <%!-- Real content layer --%>
          <%= if @task_data.ok? do %>
            <% task = @task_data.result.task %> <% form = @task_data.result.form %> <% attachments =
              @task_data.result.attachments %> <% source_attachments =
              @task_data.result.source_attachments %>
            <div class="drawer-real-content drawer-content-enter flex min-h-0 flex-1 flex-col overflow-hidden">
              <header class="flex shrink-0 items-start gap-3 border-b border-base-content/10 px-5 py-4">
                <div
                  class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-lg border"
                  style={drawer_chip_style(task)}
                >
                  <.icon name={drawer_task_icon(task)} class="size-4.5 shrink-0" />
                </div>

                <div class="min-w-0 flex-1">
                  <h2 class="text-base font-semibold leading-tight text-base-content">
                    {task.title}
                  </h2>

                  <p class="mt-0.5 text-xs text-base-content/50">
                    {gettext("Task")}
                    <%= if task.task_type do %>
                      · {task.task_type.name}
                    <% end %>
                  </p>
                </div>

                <.link
                  patch={@return_to}
                  phx-click={
                    JS.remove_attribute("data-pre-open", to: "#task-drawer")
                    |> JS.remove_attribute("data-pre-open", to: "#task-drawer-backdrop")
                  }
                  class="flex size-8 shrink-0 items-center justify-center rounded-lg text-base-content/40 transition-colors hover:bg-base-content/10 hover:text-base-content"
                  aria-label={gettext("Close")}
                >
                  <.icon name="icon-[tabler--x]" class="size-5" />
                </.link>
              </header>

              <div class="min-h-0 flex-1 overflow-y-auto px-5 py-5">
                <div class="space-y-6">
                  <section class="space-y-4">
                    <div class="grid grid-cols-2 gap-x-6 gap-y-4 md:grid-cols-4">
                      <div>
                        <p class="mb-1.5 text-xs font-medium text-base-content/50">
                          {gettext("Status")}
                        </p>

                        <div class="flex flex-col items-start gap-1.5">
                          <.status_pill
                            task_id={task.id}
                            status={task_status(task)}
                            readonly={task_status_derived?(task)}
                            readonly_reason={status_readonly_reason(task)}
                            id_suffix="-drawer"
                            myself={@myself}
                          />
                        </div>
                      </div>

                      <div>
                        <p class="mb-1.5 text-xs font-medium text-base-content/50">
                          {gettext("Priority")}
                        </p>

                        <.priority_pill
                          task_id={task.id}
                          priority={task.priority}
                          id_suffix="-drawer"
                          myself={@myself}
                        />
                      </div>

                      <div class="md:col-span-2">
                        <p class="mb-1.5 text-xs font-medium text-base-content/50">
                          {gettext("Due date")}
                        </p>

                        <.form
                          for={form}
                          id={"task-due-date-form-#{task.id}"}
                          phx-change="update_due_date"
                          phx-target={@myself}
                        >
                          <.date_picker
                            field={form[:due_date]}
                            id={"task-due-date-#{task.id}"}
                            value={datetime_input_value(task.due_date)}
                            date_format="Y-m-d\\TH:i"
                            enable_time={true}
                            time_24hr={true}
                            minute_increment={15}
                            alt_input={true}
                            alt_format="M j, Y H:i"
                            placeholder={gettext("Select date and time")}
                            required
                            class="h-8 w-full input input-sm border-base-content/15 bg-base-100 text-xs text-base-content transition-colors focus:border-primary focus:outline-none"
                          />
                        </.form>
                      </div>

                      <%= if task.task_type do %>
                        <div>
                          <p class="mb-1.5 text-xs font-medium text-base-content/50">
                            {gettext("Type")}
                          </p>

                          <span
                            class="inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-medium"
                            style={drawer_chip_style(task)}
                          >
                            <.icon name={drawer_task_icon(task)} class="size-3 shrink-0" /> {task.task_type.name}
                          </span>
                        </div>
                      <% end %>
                    </div>
                    <.task_rule_summary task={task} />
                    <div
                      :if={!!task.contact or !!task.deal}
                      class="grid grid-cols-1 gap-4 md:grid-cols-2"
                    >
                      <div :if={task.contact}>
                        <p class="mb-1.5 text-xs font-medium text-base-content/50">
                          {gettext("Contact")}
                        </p>

                        <.link
                          navigate={~p"/contacts/#{task.contact}"}
                          class="inline-flex items-center gap-2 text-sm font-medium text-primary underline-offset-2 hover:underline"
                        >
                          <.icon name="icon-[tabler--user]" class="size-3.5 text-base-content/40" /> {contact_full_name(
                            task.contact
                          )}
                        </.link>
                      </div>

                      <div :if={task.deal}>
                        <p class="mb-1.5 text-xs font-medium text-base-content/50">
                          {gettext("Deal")}
                        </p>

                        <span class="inline-flex items-center gap-1.5 text-sm text-base-content">
                          <.icon
                            name="icon-[tabler--briefcase]"
                            class="size-3.5 text-base-content/40"
                          /> {task.deal.title}
                        </span>
                      </div>
                    </div>
                    <div
                      :if={task.source_email}
                      id={"task-source-email-#{task.id}"}
                      class="rounded-lg border border-primary/20 bg-primary/5 px-3 py-3"
                    >
                      <div class="flex items-start gap-2">
                        <.icon
                          name="icon-[tabler--mail]"
                          class="mt-0.5 size-4 shrink-0 text-primary"
                        />
                        <div class="min-w-0 flex-1">
                          <p class="text-xs font-semibold text-primary">
                            {gettext("Created from email")}
                          </p>
                          <.link
                            :if={task.source_thread}
                            navigate={~p"/inbox/#{task.source_thread.id}"}
                            class="mt-1 block truncate text-sm font-medium text-base-content hover:text-primary"
                          >
                            {task.source_thread.subject || gettext("(no subject)")}
                          </.link>
                          <p class="mt-0.5 truncate text-xs text-base-content/50">
                            {task.source_email.from}
                          </p>
                        </div>
                      </div>
                    </div>
                  </section>

                  <section class="space-y-3 border-t border-base-content/10 pt-5">
                    <h3 class="text-sm font-semibold text-base-content">{gettext("Notes")}</h3>

                    <.form
                      for={form}
                      id="task-description-form"
                      phx-submit="save_description"
                      phx-target={@myself}
                      class="flex flex-col gap-3"
                    >
                      <.rich_text_input
                        id={"task-description-#{task.id}"}
                        field={form[:description]}
                        label=""
                        placeholder={gettext("Add notes, links, checklists…")}
                        class="tiptap-compact min-h-72"
                      />
                      <div class="flex justify-end">
                        <.button
                          type="submit"
                          class="btn btn-primary btn-sm gap-1.5"
                          phx-disable-with={gettext("Saving…")}
                        >
                          <.icon name="icon-[tabler--device-floppy]" class="size-3.5" /> {gettext(
                            "Save notes"
                          )}
                        </.button>
                      </div>
                    </.form>
                  </section>

                  <section class="space-y-4 border-t border-base-content/10 pt-5">
                    <h3 class="text-sm font-semibold text-base-content">{gettext("Attachments")}</h3>

                    <form
                      id="task-attachment-form"
                      phx-change="validate_attachment"
                      phx-target={@myself}
                    >
                      <.live_component
                        module={KonevoWeb.Components.DropzoneComponent}
                        id="task-attachment-dropzone"
                        upload={@uploads.task_attachment}
                        cancel_event="cancel_attachment"
                        cancel_target={@myself}
                        compact={true}
                        show_entries={true}
                      />
                    </form>

                    <KonevoWeb.Components.UploadedFilesTableComponent.render
                      id="task-attachments-table"
                      rows={attachment_rows(attachments, @current_scope.user)}
                      page={1}
                      total={length(attachments)}
                      per_page={max(length(attachments), 1)}
                      show_title={false}
                      show_footer={false}
                      show_delete={true}
                      delete_event="delete_attachment"
                      delete_target={@myself}
                      compact={true}
                      update="replace"
                      class="mt-0"
                    />
                  </section>

                  <section
                    :if={source_attachments != []}
                    class="space-y-4 border-t border-base-content/10 pt-5"
                  >
                    <h3 class="text-sm font-semibold text-base-content">
                      {gettext("Source attachments")}
                    </h3>
                    <KonevoWeb.Components.UploadedFilesTableComponent.render
                      id="task-source-attachments-table"
                      rows={attachment_rows(source_attachments, @current_scope.user)}
                      page={1}
                      total={length(source_attachments)}
                      per_page={max(length(source_attachments), 1)}
                      show_title={false}
                      show_footer={false}
                      show_delete={false}
                      compact={true}
                      update="replace"
                      class="mt-0"
                    />
                  </section>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp attachment_rows(files, user) do
    Enum.map(files, fn file ->
      {"task-attachment-#{file.id}", %{id: file.id, file: file, author: user, avatar: nil}}
    end)
  end

  defp upload_task_attachments(socket) do
    {tenant_id, owner_id} = task_attachment_owner(socket)

    results =
      consume_uploaded_entries(socket, :task_attachment, fn %{path: temp_path}, entry ->
        {:ok, process_task_attachment(temp_path, tenant_id, owner_id, entry.client_name)}
      end)

    {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))
    new_files = Enum.map(successes, fn {:ok, record} -> record end)
    current_attachments = socket.assigns.task_data.result.attachments

    new_result = %{
      socket.assigns.task_data.result
      | attachments: new_files ++ current_attachments
    }

    socket
    |> assign(:task_data, AsyncResult.ok(new_result))
    |> upload_flash(length(successes), failures)
  end

  defp task_attachment_owner(socket) do
    task = socket.assigns.task_data.result.task
    scope = socket.assigns.current_scope

    {to_string(scope.org.id), to_string(task.id)}
  end

  defp process_task_attachment(temp_path, tenant_id, owner_id, client_name) do
    case UploadProcessor.process(
           temp_path,
           :mixed_attachment,
           tenant_id,
           owner_id,
           "task",
           client_name
         ) do
      {:ok, record} -> {:ok, record}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_task_attachment_progress(:task_attachment, entry, socket) do
    if entry.done? do
      save_task_attachment(socket, entry)
    else
      {:noreply, socket}
    end
  end

  defp save_task_attachment(socket, entry) do
    if socket.assigns.task_data.ok? do
      {tenant_id, owner_id} = task_attachment_owner(socket)

      result =
        consume_uploaded_entry(socket, entry, fn %{path: temp_path} ->
          {:ok, process_task_attachment(temp_path, tenant_id, owner_id, entry.client_name)}
        end)

      handle_saved_task_attachment(socket, result)
    else
      {:noreply, cancel_upload(socket, :task_attachment, entry.ref)}
    end
  end

  defp handle_saved_task_attachment(socket, {:ok, file}) do
    current_attachments = socket.assigns.task_data.result.attachments
    new_result = %{socket.assigns.task_data.result | attachments: [file | current_attachments]}

    {:noreply,
     socket
     |> assign(:task_data, AsyncResult.ok(new_result))
     |> put_flash(:success, gettext("File attached"))}
  end

  defp handle_saved_task_attachment(socket, {:error, reason}) do
    Logger.warning("[TasksLive.DrawerComponent] Attachment upload failed: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, gettext("Could not attach file"))}
  end

  defp drawer_chip_style(task) do
    color = task_type_color(task)

    [
      "background-color: color-mix(in srgb, #{color} 16%, transparent)",
      "border-color: color-mix(in srgb, #{color} 42%, transparent)",
      "color: #{color}"
    ]
    |> Enum.join("; ")
  end

  defp drawer_task_icon(%{task_type: %{is_parent_only: true}}), do: "icon-[tabler--crown]"
  defp drawer_task_icon(%{task_type: %{name: "Epic"}}), do: "icon-[tabler--crown]"
  defp drawer_task_icon(_), do: "icon-[tabler--menu-2]"

  defp task_type_color(%{task_type: %{color: color}}) when is_binary(color) do
    if Regex.match?(~r/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/, color) do
      color
    else
      "#0ea5e9"
    end
  end

  defp task_type_color(_task), do: "#0ea5e9"

  defp task_status(task), do: Map.get(task, :effective_status, task.status)
  defp task_status_derived?(task), do: Map.get(task, :status_derived?, false)
  defp task_blocked?(task), do: Map.get(task, :blocked?, false)
  defp task_child_count(task), do: Map.get(task, :child_count, 0)
  defp task_completed_child_count(task), do: Map.get(task, :completed_child_count, 0)
  defp task_dependency_count(task), do: Map.get(task, :dependency_count, 0)
  defp task_blocking_dependency_count(task), do: Map.get(task, :blocking_dependency_count, 0)

  defp status_readonly_reason(task) do
    cond do
      task_status_derived?(task) and task_child_count(task) > 0 ->
        gettext("Status is derived from child tasks.")

      task_status_derived?(task) ->
        gettext("Epics use derived status.")

      true ->
        nil
    end
  end

  defp task_rule_error(:task_has_open_dependencies),
    do: gettext("This task is blocked by unfinished dependencies")

  defp task_rule_error(:task_has_open_children),
    do: gettext("Complete or cancel child tasks before completing this task")

  defp task_rule_error(:parent_status_is_derived),
    do: gettext("This status is derived from child tasks and cannot be changed directly")

  defp task_rule_error(:dependency_cycle), do: gettext("That dependency would create a cycle")
  defp task_rule_error(:invalid_dependency), do: gettext("A task cannot depend on itself")
  defp task_rule_error(_reason), do: gettext("Failed to update status")

  defp contact_full_name(contact) do
    [contact.first_name, contact.last_name]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> case do
      "" -> contact.email || gettext("Unknown contact")
      name -> name
    end
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""

  defp datetime_input_value(nil), do: ""

  defp datetime_input_value(%DateTime{} = date_time),
    do: Calendar.strftime(date_time, "%Y-%m-%dT%H:%M")

  defp upload_flash(socket, 0, _failures),
    do: put_flash(socket, :error, gettext("All uploads failed"))

  defp upload_flash(socket, count, []),
    do:
      put_flash(
        socket,
        :success,
        ngettext("1 file attached", "%{count} files attached", count, count: count)
      )

  defp upload_flash(socket, count, failures),
    do:
      put_flash(
        socket,
        :warning,
        ngettext("1 file attached, %{f} failed", "%{count} files attached, %{f} failed", count,
          count: count,
          f: length(failures)
        )
      )

  # ---------------------------------------------------------------------------
  # Status pill
  # ---------------------------------------------------------------------------

  attr(:task_id, :any, required: true)
  attr(:status, :atom, required: true)
  attr(:readonly, :boolean, default: false)
  attr(:readonly_reason, :string, default: nil)
  attr(:id_suffix, :string, default: "")
  attr(:myself, :any, default: nil)

  defp status_pill(assigns) do
    all_statuses = [
      {:open, "#0ea5e9", "icon-[tabler--circle-dashed]", gettext("Open")},
      {:in_progress, "#8b5cf6", "icon-[tabler--progress]", gettext("In progress")},
      {:done, "#10b981", "icon-[tabler--circle-check]", gettext("Done")},
      {:cancelled, "#94a3b8", "icon-[tabler--circle-x]", gettext("Cancelled")}
    ]

    {color, icon, label} =
      all_statuses
      |> Enum.find(
        {:unknown, "#94a3b8", "icon-[tabler--circle-dashed]",
         Phoenix.Naming.humanize(assigns.status)},
        fn {s, _, _, _} -> s == assigns.status end
      )
      |> then(fn {_, c, i, l} -> {c, i, l} end)

    assigns =
      assign(assigns,
        color: color,
        icon: icon,
        label: label,
        all_statuses: all_statuses
      )

    ~H"""
    <div
      id={"status-pill-#{@task_id}#{@id_suffix}"}
      phx-hook={if(@readonly, do: nil, else: "RowMenu")}
      class="relative"
    >
      <%= if @readonly do %>
        <span
          title={@readonly_reason}
          class="inline-flex w-full items-center gap-1 rounded-md border px-2.5 py-1 text-xs font-medium"
          style={pill_style_muted(@color)}
        >
          <.icon name={@icon} class="size-3 shrink-0" /> {@label}
        </span>
      <% else %>
        <button
          type="button"
          data-toggle
          aria-label={gettext("Change status")}
          class="inline-flex w-full cursor-pointer items-center gap-1 rounded-md border px-2.5 py-1 text-xs font-medium transition-opacity hover:opacity-80"
          style={pill_style(@color)}
        >
          <.icon name={@icon} class="size-3 shrink-0" /> {@label}
          <.icon name="icon-[tabler--chevron-down]" class="ml-auto size-3 shrink-0 opacity-60" />
        </button>
        <ul
          data-panel
          class="row-menu-closed z-50 w-44 space-y-0.5 overflow-hidden rounded-xl border border-base-content/10 bg-base-100 p-1.5 shadow-2xl shadow-base-content/15"
          role="menu"
        >
          <li :for={{val, color, icon, label} <- @all_statuses}>
            <button
              type="button"
              phx-click="update_status"
              phx-value-id={@task_id}
              phx-value-status={val}
              phx-target={@myself}
              class="inline-flex w-full cursor-pointer items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-medium transition-opacity hover:opacity-85"
              style={pill_style_option(color, @status == val)}
              role="menuitem"
            >
              <.icon name={icon} class="size-3 shrink-0" /> {label}
              <.icon
                :if={@status == val}
                name="icon-[tabler--check]"
                class="ml-auto size-3 shrink-0"
              />
            </button>
          </li>
        </ul>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Priority pill
  # ---------------------------------------------------------------------------

  attr(:task_id, :string, required: true)
  attr(:priority, :atom, required: true)
  attr(:id_suffix, :string, default: "")
  attr(:myself, :any, default: nil)

  defp priority_pill(assigns) do
    all_priorities = [
      {:low, "#64748b", "icon-[tabler--arrow-down]", gettext("Low")},
      {:normal, "#3b82f6", "icon-[tabler--arrow-right]", gettext("Normal")},
      {:high, "#f97316", "icon-[tabler--arrow-up]", gettext("High")},
      {:urgent, "#ef4444", "icon-[tabler--alert-triangle]", gettext("Urgent")}
    ]

    {color, icon, label} =
      all_priorities
      |> Enum.find(
        {:unknown, "#64748b", "icon-[tabler--minus]", Phoenix.Naming.humanize(assigns.priority)},
        fn {p, _, _, _} -> p == assigns.priority end
      )
      |> then(fn {_, c, i, l} -> {c, i, l} end)

    assigns =
      assign(assigns,
        color: color,
        icon: icon,
        label: label,
        all_priorities: all_priorities
      )

    ~H"""
    <div id={"priority-pill-#{@task_id}#{@id_suffix}"} phx-hook="RowMenu" class="relative">
      <button
        type="button"
        data-toggle
        aria-label={gettext("Change priority")}
        class="inline-flex w-full cursor-pointer items-center gap-1 rounded-md border px-2.5 py-1 text-xs font-medium transition-opacity hover:opacity-80"
        style={pill_style(@color)}
      >
        <span class={[@icon, "size-3 shrink-0"]} /> {@label}
        <span class="icon-[tabler--chevron-down] ml-auto size-3 shrink-0 opacity-60" />
      </button>
      <ul
        data-panel
        class="row-menu-closed z-50 w-40 space-y-0.5 overflow-hidden rounded-xl border border-base-content/10 bg-base-100 p-1.5 shadow-2xl shadow-base-content/15"
        role="menu"
      >
        <li :for={{val, color, icon, label} <- @all_priorities}>
          <button
            type="button"
            phx-click="update_priority"
            phx-value-id={@task_id}
            phx-value-priority={val}
            phx-target={@myself}
            class="inline-flex w-full cursor-pointer items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-medium transition-opacity hover:opacity-85"
            style={pill_style_option(color, @priority == val)}
            role="menuitem"
          >
            <span class={[icon, "size-3 shrink-0"]} /> {label}
            <span :if={@priority == val} class="icon-[tabler--check] ml-auto size-3 shrink-0" />
          </button>
        </li>
      </ul>
    </div>
    """
  end

  attr(:task, :any, required: true)

  defp task_rule_summary(assigns) do
    ~H"""
    <div
      :if={task_child_count(@task) > 0 or task_dependency_count(@task) > 0}
      id={"task-rule-summary-#{@task.id}"}
      class="rounded-lg border border-base-content/10 bg-base-200/40 px-3 py-3"
    >
      <div class="flex flex-wrap gap-2">
        <span
          :if={task_child_count(@task) > 0}
          class="inline-flex items-center gap-1.5 rounded-md border border-base-content/10 bg-base-100 px-2.5 py-1 text-xs font-medium text-base-content/65"
        >
          <.icon name="icon-[tabler--checklist]" class="size-3.5 text-base-content/40" /> {task_completed_child_count(
            @task
          )}/{task_child_count(@task)} {gettext("children done")}
        </span>
        <span
          :if={task_status_derived?(@task)}
          class="inline-flex items-center gap-1.5 rounded-md border border-primary/20 bg-primary/10 px-2.5 py-1 text-xs font-medium text-primary"
        >
          <.icon name="icon-[tabler--hierarchy]" class="size-3.5" /> {gettext("Status derived")}
        </span>
        <span
          :if={task_blocked?(@task)}
          class="inline-flex items-center gap-1.5 rounded-md border border-error/25 bg-error/10 px-2.5 py-1 text-xs font-medium text-error"
        >
          <.icon name="icon-[tabler--lock]" class="size-3.5" /> {ngettext(
            "Blocked by 1 task",
            "Blocked by %{count} tasks",
            task_blocking_dependency_count(@task),
            count: task_blocking_dependency_count(@task)
          )}
        </span>
        <span
          :if={task_dependency_count(@task) > 0 and not task_blocked?(@task)}
          class="inline-flex items-center gap-1.5 rounded-md border border-success/20 bg-success/10 px-2.5 py-1 text-xs font-medium text-success"
        >
          <.icon name="icon-[tabler--circle-check]" class="size-3.5" /> {gettext(
            "Dependencies complete"
          )}
        </span>
      </div>
    </div>
    """
  end

  defp pill_style(color) do
    [
      "background-color: color-mix(in srgb, #{color} 14%, transparent)",
      "border-color: color-mix(in srgb, #{color} 35%, transparent)",
      "color: #{color}"
    ]
    |> Enum.join("; ")
  end

  defp pill_style_muted(color) do
    [
      "background-color: color-mix(in srgb, var(--color-base-100) 86%, var(--color-base-200))",
      "border-color: color-mix(in srgb, #{color} 42%, var(--color-base-content) 12%)",
      "color: color-mix(in srgb, #{color} 72%, var(--color-base-content))"
    ]
    |> Enum.join("; ")
  end

  defp pill_style_option(color, active) do
    bg_pct = if active, do: "22%", else: "14%"
    border_pct = if active, do: "50%", else: "35%"

    [
      "background-color: color-mix(in srgb, #{color} #{bg_pct}, transparent)",
      "border-color: color-mix(in srgb, #{color} #{border_pct}, transparent)",
      "color: #{color}"
    ]
    |> Enum.join("; ")
  end
end
