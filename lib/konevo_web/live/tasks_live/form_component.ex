defmodule KonevoWeb.TasksLive.FormComponent do
  use KonevoWeb, :live_component
  import LiveSelect

  alias Konevo.{Companies, Contacts, Tasks}

  @impl true
  def update(assigns, socket) do
    parent_task_id = assigns.parent_task_id || assigns.task.parent_task_id

    task =
      assigns.task
      |> Map.put(:parent_task_id, parent_task_id)
      |> put_default_task_type(assigns.task_types, parent_task_id)

    changeset = Tasks.change_task(task)
    auto_parent_epic = suggested_parent_epic(assigns.current_scope, task)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:task, task)
     |> assign(:form, to_form(changeset, as: :task))
     |> assign(:contact_options, build_contact_options(assigns.current_scope, task))
     |> assign(:company_options, build_company_options(assigns.current_scope, task))
     |> assign(:depends_on_task_id, "")
     |> assign(:auto_parent_epic, auto_parent_epic)
     |> assign(:parent_mode, default_parent_mode(parent_task_id, auto_parent_epic))
     |> assign_new(:patch, fn -> ~p"/tasks" end)
     |> assign_new(:cancel_event, fn -> nil end)}
  end

  @impl true
  def handle_event("live_select_change", %{"field" => field, "id" => id, "text" => text}, socket) do
    options =
      field
      |> live_select_field()
      |> live_select_options(socket, text)

    send_update(LiveSelect.Component, id: id, options: options)
    {:noreply, socket}
  end

  def handle_event("validate", %{"task" => task_params}, socket) do
    auto_parent_epic = suggested_parent_epic(socket.assigns.current_scope, task_params)
    parent_mode = parent_mode_from_params(socket, task_params, auto_parent_epic)

    changeset =
      socket.assigns.task
      |> Tasks.change_task(normalize_due_date(task_params))
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: :task))
     |> assign(:depends_on_task_id, Map.get(task_params, "depends_on_task_id", ""))
     |> assign(:auto_parent_epic, auto_parent_epic)
     |> assign(:parent_mode, parent_mode)}
  end

  def handle_event("save", %{"task" => task_params}, socket) do
    params =
      task_params
      |> Map.put("parent_task_id", parent_task_id(socket, task_params))
      |> Map.drop(["depends_on_task_id"])

    case Tasks.create_task(socket.assigns.current_scope, params) do
      {:ok, task} ->
        dependency_result = maybe_add_dependency(socket, task, task_params["depends_on_task_id"])
        send(self(), {__MODULE__, {:saved, task, dependency_result}})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :task))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Task could not be created"))}
    end
  end

  defp maybe_add_dependency(_socket, _task, value) when value in [nil, ""], do: :ok

  defp maybe_add_dependency(socket, task, value) do
    dependency = Tasks.get_task!(socket.assigns.current_scope, value)

    case Tasks.add_dependency(socket.assigns.current_scope, task, dependency) do
      {:ok, _dependency} -> :ok
      {:error, _reason} -> {:error, :dependency}
    end
  end

  defp parent_task_id(socket, params) do
    cond do
      socket.assigns.parent_task_id ->
        socket.assigns.parent_task_id

      auto_parent_mode?(socket, params) ->
        ""

      true ->
        Map.get(params, "parent_task_id")
    end
  end

  defp default_parent_mode(parent_task_id, _auto_parent_epic) when not is_nil(parent_task_id),
    do: "manual"

  defp default_parent_mode(_parent_task_id, nil), do: "manual"
  defp default_parent_mode(_parent_task_id, _auto_parent_epic), do: "auto"

  defp parent_mode_from_params(socket, params, auto_parent_epic) do
    mode = Map.get(params, "parent_mode", socket.assigns.parent_mode)

    if mode == "auto" and auto_parent_epic do
      "auto"
    else
      "manual"
    end
  end

  defp auto_parent_mode?(socket, params) do
    mode = Map.get(params, "parent_mode", socket.assigns.parent_mode)
    mode == "auto" and socket.assigns.auto_parent_epic
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:selected_parent_task_id, selected_parent_task_id(assigns))
      |> assign(:selected_task_type_parent_only?, selected_task_type_parent_only?(assigns))

    ~H"""
    <div>
      <%!-- Header --%>
      <div class="mb-6 flex items-center gap-3">
        <div class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary/10">
          <.icon name="icon-[tabler--checkbox]" class="size-5 text-primary" />
        </div>

        <div>
          <h2 class="text-base font-semibold text-base-content">{gettext("New task")}</h2>
          <p class="text-xs text-base-content/50">
            {gettext("Fill in the details to create a new task")}
          </p>
        </div>
      </div>

      <.form
        for={@form}
        id="task-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <input
          type="hidden"
          name={@form[:source_thread_id].name}
          value={@form[:source_thread_id].value}
        />
        <input
          type="hidden"
          name={@form[:source_email_id].name}
          value={@form[:source_email_id].value}
        />
        <input type="hidden" name={@form[:deal_id].name} value={@form[:deal_id].value} />

        <%!-- Core info --%>
        <div class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
          <.icon name="icon-[tabler--info-circle]" class="size-3.5" />
          {gettext("Task info")}
        </div>

        <div class="mb-4 flex flex-col gap-4 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <.input
            field={@form[:title]}
            type="text"
            label={gettext("Title")}
            placeholder={gettext("e.g. Follow up with Acme")}
            class="w-full input"
            required
          />
          <.input
            field={@form[:description]}
            type="textarea"
            label={gettext("Description")}
            rows="3"
            class="w-full textarea"
          />
        </div>

        <%!-- Planning --%>
        <div class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
          <.icon name="icon-[tabler--calendar-time]" class="size-3.5" />
          {gettext("Planning")}
        </div>

        <div class="mb-4 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.task_type_select
              field={@form[:task_type_id]}
              myself={@myself}
              label={gettext("Type")}
              options={task_type_live_options(@task_types, @selected_parent_task_id)}
            />
            <.task_choice_select
              field={@form[:priority]}
              myself={@myself}
              label={gettext("Priority")}
              options={priority_live_options()}
              icon="icon-[tabler--flag]"
              placeholder={gettext("Choose priority")}
            />
          </div>

          <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.task_choice_select
              field={@form[:status]}
              myself={@myself}
              label={gettext("Status")}
              options={status_live_options()}
              icon="icon-[tabler--circle-dashed]"
              placeholder={gettext("Choose status")}
              disabled={@selected_task_type_parent_only?}
            />
            <.input
              field={@form[:due_date]}
              type="datetime-local"
              label={gettext("Due date")}
              class="w-full input"
              required
            />
          </div>
        </div>

        <%!-- Relationships --%>
        <div class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
          <.icon name="icon-[tabler--hierarchy]" class="size-3.5" />
          {gettext("Relationships")}
        </div>

        <div class="mb-6 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <div class="mb-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.contact_select
              field={@form[:contact_id]}
              myself={@myself}
              label={gettext("Contact")}
              options={@contact_options}
            />
            <.company_select
              field={@form[:company_id]}
              myself={@myself}
              label={gettext("Company")}
              options={@company_options}
            />
          </div>

          <div
            :if={@auto_parent_epic && is_nil(@parent_task_id)}
            id="task-filing-mode"
            class="mb-4 rounded-lg border border-base-content/10 bg-base-100 p-3"
          >
            <div class="mb-3 flex items-center justify-between gap-3">
              <span class="text-sm font-semibold text-base-content">{gettext("Filing")}</span>
              <div class="inline-flex items-center gap-1">
                <label class="btn btn-xs gap-1.5">
                  <input
                    type="radio"
                    name={@form[:parent_mode].name}
                    value="auto"
                    checked={@parent_mode == "auto"}
                    class="radio radio-xs"
                  />
                  <.icon name="icon-[tabler--sparkles]" class="size-3.5" />
                  {gettext("Automatic")}
                </label>
                <label class="btn btn-xs gap-1.5">
                  <input
                    type="radio"
                    name={@form[:parent_mode].name}
                    value="manual"
                    checked={@parent_mode == "manual"}
                    class="radio radio-xs"
                  />
                  <.icon name="icon-[tabler--subtask]" class="size-3.5" />
                  {gettext("Manual")}
                </label>
              </div>
            </div>

            <div
              :if={@parent_mode == "auto"}
              id="task-auto-parent-preview"
              class="flex items-center gap-3 rounded-md border border-primary/15 bg-primary/5 px-3 py-2.5 text-sm text-base-content"
            >
              <span class="flex size-8 shrink-0 items-center justify-center rounded-md border border-primary/20 bg-primary/10 text-primary">
                <.icon name={@auto_parent_epic.icon} class="size-4" />
              </span>
              <div class="min-w-0 flex-1">
                <p class="text-xs font-semibold uppercase tracking-wide text-base-content/45">
                  {gettext("Filed under")}
                </p>
                <p class="truncate font-semibold text-base-content">
                  {@auto_parent_epic.title}
                </p>
              </div>
            </div>
          </div>

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.task_relation_select
              :if={@parent_mode == "manual" || is_nil(@auto_parent_epic) || @parent_task_id}
              field={@form[:parent_task_id]}
              myself={@myself}
              label={gettext("Parent")}
              options={parent_task_live_options(@task_options, @selected_task_type_parent_only?)}
              placeholder={gettext("Search parent tasks")}
              empty_label={gettext("No parent")}
              disabled={not is_nil(@parent_task_id) or @selected_task_type_parent_only?}
            />
            <.task_relation_select
              field={@form[:depends_on_task_id]}
              myself={@myself}
              label={gettext("Depends on")}
              value={@depends_on_task_id}
              options={task_live_options(@task_options)}
              placeholder={gettext("Search blocking tasks")}
              empty_label={gettext("No dependency")}
            />
          </div>
        </div>

        <%!-- Actions --%>
        <div class="flex justify-end gap-3">
          <.button
            :if={@cancel_event}
            type="button"
            class="btn btn-outline border-base-content/20 text-base-content/70 hover:bg-base-200/70 hover:border-base-content/30"
            phx-click={@cancel_event}
          >
            {gettext("Cancel")}
          </.button>
          <.button
            :if={!@cancel_event}
            type="button"
            class="btn btn-outline border-base-content/20 text-base-content/70 hover:bg-base-200/70 hover:border-base-content/30"
            phx-click={JS.patch(@patch)}
          >
            {gettext("Cancel")}
          </.button>
          <.button
            type="submit"
            phx-disable-with={gettext("Saving...")}
            class="btn btn-primary gap-1.5"
          >
            <.icon name="icon-[tabler--device-floppy]" class="size-4" />
            {gettext("Create task")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  defp normalize_due_date(%{"due_date" => due_date} = params) when is_binary(due_date) do
    with {:error, _reason} <- put_naive_due_date(params, due_date),
         {:error, _reason} <- put_naive_due_date(params, due_date <> ":00") do
      params
    else
      {:ok, params} -> params
    end
  end

  defp normalize_due_date(params), do: params

  defp put_naive_due_date(params, due_date) do
    case NaiveDateTime.from_iso8601(due_date) do
      {:ok, naive} -> {:ok, Map.put(params, "due_date", DateTime.from_naive!(naive, "Etc/UTC"))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_default_task_type(%{task_type_id: task_type_id} = task, _task_types, _parent_task_id)
       when not is_nil(task_type_id),
       do: task

  defp put_default_task_type(task, task_types, parent_task_id) do
    case default_task_type_id(task_types, parent_task_id) do
      nil -> task
      task_type_id -> %{task | task_type_id: task_type_id}
    end
  end

  defp default_task_type_id(task_types, nil) do
    task_types
    |> Enum.reject(& &1.is_parent_only)
    |> List.first()
    |> case do
      nil -> task_types |> List.first() |> task_type_id()
      task_type -> task_type.id
    end
  end

  defp default_task_type_id(task_types, _parent_task_id) do
    task_types
    |> Enum.reject(& &1.is_parent_only)
    |> List.first()
    |> task_type_id()
  end

  defp task_type_id(nil), do: nil
  defp task_type_id(task_type), do: task_type.id

  defp suggested_parent_epic(scope, attrs) do
    case Tasks.suggested_parent_epic(scope, attrs) do
      {:ok, parent} -> parent
      {:error, _reason} -> nil
    end
  end

  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:myself, :any, required: true)
  attr(:label, :string, required: true)
  attr(:options, :list, required: true)

  defp task_type_select(assigns) do
    ~H"""
    <.task_live_select
      field={@field}
      myself={@myself}
      label={@label}
      options={@options}
      icon="icon-[tabler--category]"
      placeholder={gettext("Choose task type")}
      allow_clear={false}
    />
    """
  end

  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:myself, :any, required: true)
  attr(:label, :string, required: true)
  attr(:options, :list, required: true)
  attr(:icon, :string, required: true)
  attr(:placeholder, :string, required: true)
  attr(:disabled, :boolean, default: false)

  defp task_choice_select(assigns) do
    ~H"""
    <.task_live_select
      field={@field}
      myself={@myself}
      label={@label}
      options={@options}
      icon={@icon}
      placeholder={@placeholder}
      allow_clear={false}
      disabled={@disabled}
    />
    """
  end

  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:myself, :any, required: true)
  attr(:label, :string, required: true)
  attr(:options, :list, required: true)
  attr(:placeholder, :string, required: true)
  attr(:empty_label, :string, required: true)
  attr(:disabled, :boolean, default: false)
  attr(:value, :any, default: nil)

  defp task_relation_select(assigns) do
    options = [
      %{label: assigns.empty_label, value: "", icon: "icon-[tabler--ban]"} | assigns.options
    ]

    assigns =
      assigns
      |> assign(:options, options)
      |> assign(:value, select_value(assigns.value, assigns.field.value))

    ~H"""
    <.task_live_select
      field={@field}
      myself={@myself}
      label={@label}
      options={@options}
      value={@value}
      icon="icon-[tabler--subtask]"
      placeholder={@placeholder}
      allow_clear={true}
      disabled={@disabled}
    />
    """
  end

  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:myself, :any, required: true)
  attr(:label, :string, required: true)
  attr(:options, :list, required: true)
  attr(:icon, :string, required: true)
  attr(:placeholder, :string, required: true)
  attr(:allow_clear, :boolean, default: true)
  attr(:disabled, :boolean, default: false)
  attr(:value, :any, default: nil)

  defp task_live_select(assigns) do
    errors =
      if Phoenix.Component.used_input?(assigns.field) do
        Enum.map(assigns.field.errors, &translate_error/1)
      else
        []
      end

    assigns =
      assigns
      |> assign(:errors, errors)
      |> assign(:select_value, select_value(assigns.value, assigns.field.value))
      |> assign(
        :selected_color,
        selected_option_color(assigns.options, select_value(assigns.value, assigns.field.value))
      )

    ~H"""
    <div class="fieldset flex w-full flex-col gap-2">
      <span class="label">{@label}</span>
      <div class="relative w-full">
        <span class="pointer-events-none absolute inset-y-0 left-3 z-20 flex items-center">
          <span
            class="flex size-6 items-center justify-center rounded-md border"
            style={live_select_gutter_style(@selected_color)}
          >
            <.icon name={@icon} class="size-3.5" />
          </span>
        </span>
        <.live_select
          field={@field}
          options={@options}
          value={@select_value}
          value_mapper={&live_select_value(&1, @options)}
          phx-target={@myself}
          placeholder={@placeholder}
          allow_clear={@allow_clear}
          disabled={@disabled}
          style={:none}
          debounce={120}
          update_min_len={0}
          container_class="relative w-full"
          text_input_class="input w-full pl-11 pr-8 font-medium placeholder:text-base-content/40 disabled:bg-base-200/50"
          text_input_selected_class="border-base-content/15"
          clear_button_class="task-live-select-clear absolute inset-y-0 right-1.5 z-20 flex w-8 items-center justify-center leading-none text-base-content/35 transition-colors hover:text-base-content/70"
          dropdown_class="absolute left-0 top-[calc(100%+4px)] z-[300] w-full max-h-64 overflow-y-auto rounded-lg border border-base-content/10 bg-base-100 p-1.5 shadow-xl shadow-base-content/10"
          option_class="flex w-full items-center gap-2.5 rounded-md px-2.5 py-2 text-sm"
          available_option_class="cursor-pointer rounded-md hover:bg-base-200/70"
          selected_option_class="cursor-pointer rounded-md bg-base-200/70 font-semibold"
          active_option_class="bg-base-200"
        >
          <:option :let={opt}>
            <span
              class="flex size-7 shrink-0 items-center justify-center rounded-md border"
              style={live_select_option_icon_style(opt)}
            >
              <.icon name={Map.get(opt, :icon, "icon-[tabler--checkbox]")} class="size-3.5" />
            </span>
            <span class={[
              "min-w-0 flex-1 truncate",
              opt.value in [nil, ""] && "italic text-base-content/40"
            ]}>
              {opt.label}
            </span>
            <.icon
              :if={opt.selected}
              name="icon-[tabler--check]"
              class="size-3.5 shrink-0"
              style={live_select_icon_color(opt)}
            />
          </:option>
          <:clear_button>
            <.icon name="icon-[tabler--x]" class="size-4" />
          </:clear_button>
        </.live_select>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp live_select_field("task_" <> field), do: field
  defp live_select_field(field), do: field

  defp live_select_options("contact_id", socket, text) do
    [
      %{label: gettext("-- No contact --"), value: nil}
      | build_contact_search_options(socket.assigns.current_scope, text)
    ]
  end

  defp live_select_options("company_id", socket, text) do
    [
      %{label: gettext("No company"), value: nil}
      | build_company_search_options(socket.assigns.current_scope, text)
    ]
  end

  defp live_select_options("status", _socket, text),
    do: filter_live_options(status_live_options(), text)

  defp live_select_options("priority", _socket, text),
    do: filter_live_options(priority_live_options(), text)

  defp live_select_options("task_type_id", socket, text),
    do:
      socket.assigns.task_types
      |> task_type_live_options(selected_parent_task_id(socket.assigns))
      |> filter_live_options(text)

  defp live_select_options("parent_task_id", socket, text) do
    options =
      socket.assigns.task_options
      |> parent_task_live_options(selected_task_type_parent_only?(socket.assigns))
      |> filter_live_options(text)

    [
      %{label: gettext("No parent"), value: "", icon: "icon-[tabler--ban]"}
      | options
    ]
  end

  defp live_select_options("depends_on_task_id", socket, text) do
    [
      %{label: gettext("No dependency"), value: "", icon: "icon-[tabler--ban]"}
      | filter_live_options(task_live_options(socket.assigns.task_options), text)
    ]
  end

  defp live_select_options(_field, _socket, _text), do: []

  defp filter_live_options(options, text) do
    query = text |> to_string() |> String.trim() |> String.downcase()

    Enum.filter(options, fn option ->
      query == "" or String.contains?(String.downcase(to_string(option.label)), query)
    end)
  end

  defp task_type_live_options(task_types, nil), do: do_task_type_live_options(task_types)

  defp task_type_live_options(task_types, _parent_task_id) do
    task_types
    |> Enum.reject(& &1.is_parent_only)
    |> do_task_type_live_options()
  end

  defp do_task_type_live_options(task_types) do
    Enum.map(task_types, fn task_type ->
      %{
        label: task_type.name,
        value: task_type.id,
        icon: task_type.icon || task_type_icon(task_type),
        color: valid_hex_color(task_type.color, "#0ea5e9")
      }
    end)
  end

  defp parent_task_live_options(_tasks, true), do: []
  defp parent_task_live_options(tasks, false), do: task_live_options(tasks)

  defp task_live_options(tasks) do
    Enum.map(tasks, fn task ->
      %{
        label: task.title,
        value: task.id,
        icon: "icon-[tabler--subtask]",
        color: "#0ea5e9"
      }
    end)
  end

  defp selected_parent_task_id(assigns) do
    assigns.parent_task_id || normalize_id(assigns.form[:parent_task_id].value)
  end

  defp selected_task_type_parent_only?(assigns) do
    task_type_id = normalize_id(assigns.form[:task_type_id].value)

    Enum.any?(assigns.task_types, fn task_type ->
      task_type.id == task_type_id and task_type.is_parent_only
    end)
  end

  defp normalize_id(value) when value in [nil, ""], do: nil
  defp normalize_id(value) when is_integer(value), do: value

  defp normalize_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp build_contact_options(scope, task) do
    base = build_contact_search_options(scope, "")
    existing = resolve_contact_option(scope, task)

    prepend_existing_option(base, existing)
  end

  defp build_contact_search_options(scope, text) do
    scope
    |> Contacts.search_contacts(text, 20)
    |> Enum.map(&contact_option/1)
  end

  defp resolve_contact_option(_scope, %{contact: %Contacts.Contact{} = contact}),
    do: contact_option(contact)

  defp resolve_contact_option(scope, %{contact_id: id}) when not is_nil(id) do
    scope
    |> Contacts.get_contact!(id)
    |> contact_option()
  end

  defp resolve_contact_option(_scope, _task), do: nil

  defp contact_option(contact) do
    name =
      [contact.first_name, contact.last_name]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")

    label =
      cond do
        name != "" and contact.email not in [nil, ""] -> "#{name} (#{contact.email})"
        name != "" -> name
        true -> contact.email || gettext("Unknown contact")
      end

    %{label: label, value: contact.id}
  end

  defp build_company_options(scope, task) do
    base = build_company_search_options(scope, "")
    existing = resolve_company_option(scope, task)

    prepend_existing_option(base, existing)
  end

  defp build_company_search_options(scope, text) do
    scope
    |> Companies.search_companies(text, 20)
    |> Enum.map(&%{label: &1.name, value: &1.id})
  end

  defp resolve_company_option(_scope, %{company: %Companies.Company{} = company}),
    do: %{label: company.name, value: company.id}

  defp resolve_company_option(scope, %{company_id: id}) when not is_nil(id) do
    company = Companies.get_company!(scope, id)
    %{label: company.name, value: company.id}
  end

  defp resolve_company_option(_scope, _task), do: nil

  defp prepend_existing_option(base, nil), do: base

  defp prepend_existing_option(base, existing) do
    if Enum.any?(base, &(&1.value == existing.value)) do
      base
    else
      [existing | base]
    end
  end

  defp status_live_options do
    [
      %{label: gettext("Open"), value: "open", icon: "icon-[tabler--circle]", color: "#0ea5e9"},
      %{
        label: gettext("In progress"),
        value: "in_progress",
        icon: "icon-[tabler--circle-half-2]",
        color: "#8b5cf6"
      },
      %{
        label: gettext("Done"),
        value: "done",
        icon: "icon-[tabler--circle-check-filled]",
        color: "#10b981"
      },
      %{
        label: gettext("Cancelled"),
        value: "cancelled",
        icon: "icon-[tabler--circle-x]",
        color: "#94a3b8"
      }
    ]
  end

  defp priority_live_options do
    [
      %{
        label: gettext("Low"),
        value: "low",
        icon: "icon-[tabler--flag-filled]",
        color: "#64748b"
      },
      %{
        label: gettext("Normal"),
        value: "normal",
        icon: "icon-[tabler--flag-filled]",
        color: "#3b82f6"
      },
      %{
        label: gettext("High"),
        value: "high",
        icon: "icon-[tabler--flag-filled]",
        color: "#f97316"
      },
      %{
        label: gettext("Urgent"),
        value: "urgent",
        icon: "icon-[tabler--flag-filled]",
        color: "#ef4444"
      }
    ]
  end

  defp task_type_icon(%{is_parent_only: true}), do: "icon-[tabler--crown]"
  defp task_type_icon(%{name: "Epic"}), do: "icon-[tabler--crown]"
  defp task_type_icon(_task_type), do: "icon-[tabler--menu-2]"

  # LiveSelect sends form values back from the browser as strings. Match those
  # values against the option value so integer foreign keys retain their label
  # (for example, "6" remains "Task" rather than being rendered as "6").
  defp live_select_value(value, options) when is_binary(value) do
    Enum.find_value(options, value, fn option ->
      if to_string(option.value) == value, do: option.value
    end)
  end

  defp live_select_value(value, _options) when is_atom(value), do: Atom.to_string(value)
  defp live_select_value(value, _options), do: value

  defp select_value(nil, field_value), do: field_value
  defp select_value("", field_value), do: field_value
  defp select_value(value, _field_value), do: value

  defp selected_option_color(options, value) do
    value = live_select_value(value, options)

    options
    |> Enum.find(fn option -> option.value == value end)
    |> case do
      %{color: color} -> valid_hex_color(color, "#0ea5e9")
      _option -> "#0ea5e9"
    end
  end

  defp live_select_gutter_style(color) do
    color = valid_hex_color(color, "#0ea5e9")

    [
      "background-color: color-mix(in srgb, #{color} 14%, transparent)",
      "border-color: color-mix(in srgb, #{color} 35%, transparent)",
      "color: #{color}"
    ]
    |> Enum.join("; ")
  end

  defp live_select_option_icon_style(%{value: value}) when value in [nil, ""] do
    [
      "background-color: color-mix(in srgb, var(--color-base-content) 8%, transparent)",
      "border-color: color-mix(in srgb, var(--color-base-content) 12%, transparent)",
      "color: color-mix(in srgb, var(--color-base-content) 38%, transparent)"
    ]
    |> Enum.join("; ")
  end

  defp live_select_option_icon_style(option) do
    color = option |> Map.get(:color) |> valid_hex_color("#0ea5e9")

    [
      "background-color: color-mix(in srgb, #{color} 14%, transparent)",
      "border-color: color-mix(in srgb, #{color} 35%, transparent)",
      "color: #{color}"
    ]
    |> Enum.join("; ")
  end

  defp live_select_icon_color(option) do
    color = option |> Map.get(:color) |> valid_hex_color("#0ea5e9")
    "color: #{color}"
  end

  defp valid_hex_color(color, fallback)
       when is_binary(color) and byte_size(color) in [4, 7] do
    if Regex.match?(~r/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/, color) do
      color
    else
      fallback
    end
  end

  defp valid_hex_color(_color, fallback), do: fallback
end
