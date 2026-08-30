defmodule KonevoWeb.DealsLive.FormComponent do
  use KonevoWeb, :live_component
  import LiveSelect

  alias Konevo.Accounts
  alias Konevo.{Contacts, Deals}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Header --%>
      <div class="mb-6 flex items-center gap-3">
        <div class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary/10">
          <span class={[
            "size-5 text-primary",
            "icon-[tabler--briefcase]"
          ]} />
        </div>

        <div>
          <h2 class="text-base font-semibold text-base-content">{@title}</h2>

          <p class="text-xs text-base-content/50">
            {if @action == :new,
              do: gettext("Fill in the details to create a new deal"),
              else: gettext("Update the deal information below")}
          </p>
        </div>
      </div>

      <.form
        for={@form}
        id="deal-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <%!-- Core info --%>
        <div class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
          <span class="icon-[tabler--info-circle] size-3.5" /> {gettext("Deal info")}
        </div>

        <div class="mb-4 flex flex-col gap-4 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <.input
            field={@form[:title]}
            type="text"
            label={gettext("Title")}
            placeholder={gettext("e.g. Enterprise subscription – Acme Corp")}
            class="input h-10 w-full"
          />
          <%!-- Contact live search --%>
          <.contact_select
            field={@form[:contact_id]}
            myself={@myself}
            label={gettext("Contact")}
            options={@contact_options}
            show_errors={@submit_attempted?}
            required
          />
          <%!-- Stage --%>
          <div class="fieldset">
            <label class="label">
              {gettext("Stage")}<span class="ml-0.5 text-error" aria-hidden="true">*</span>
            </label>
            <div class="flex flex-wrap gap-2">
              <label :for={stage <- @stages} class="cursor-pointer">
                <input
                  type="radio"
                  name={@form[:stage_id].name}
                  value={stage.id}
                  id={"stage-opt-#{stage.id}"}
                  class="sr-only peer"
                  checked={to_string(@form[:stage_id].value) == to_string(stage.id)}
                  required
                />
                <span class={[
                  "inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-sm font-medium transition-all select-none cursor-pointer",
                  "border-base-content/40 bg-base-100 text-base-content/60 hover:border-base-content/60",
                  "peer-checked:border-primary peer-checked:bg-primary/10 peer-checked:text-primary peer-checked:font-semibold"
                ]}>
                  <span
                    class="size-2 rounded-full"
                    style={"background-color: #{stage.color || "#9ca3af"}"}
                  /> {stage.name}
                </span>
              </label>
            </div>

            <.error :for={msg <- field_errors(@form[:stage_id])}>{msg}</.error>
          </div>
        </div>
        <%!-- Value & probability --%>
        <div class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
          <span class="icon-[tabler--coin] size-3.5" /> {gettext("Value")}
        </div>

        <div class="mb-4 flex flex-col gap-4 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div class="sm:col-span-2">
              <.input
                field={@form[:value]}
                type="number"
                label={gettext("Deal value")}
                placeholder="0"
                min="0"
                step="0.01"
                class="input h-10 w-full"
              />
            </div>

            <.currency_picker field={@form[:currency]} myself={@myself} />
          </div>

          <div>
            <.input
              field={@form[:probability]}
              type="range"
              label={gettext("Win probability")}
              min="0"
              max="100"
              step="1"
              suffix="%"
              class="range range-primary w-full"
            />
          </div>
        </div>
        <%!-- Timeline --%>
        <div class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
          <span class="icon-[tabler--calendar] size-3.5" /> {gettext("Timeline")}
        </div>

        <div class="mb-4 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input
              field={@form[:expected_close_date]}
              type="date"
              label={gettext("Expected close date")}
              class="input h-10 w-full"
            />
            <.source_picker
              field={@form[:source]}
              myself={@myself}
            />
          </div>
        </div>
        <%!-- Owner --%>
        <div class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
          <span class="icon-[tabler--user-check] size-3.5" /> {gettext("Owner")}
        </div>

        <div class="mb-6 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <.owner_select
            field={@form[:owner_id]}
            label={gettext("Assigned to")}
            options={@owner_options}
            myself={@myself}
          />
        </div>
        <%!-- Actions --%>
        <div class="flex justify-end gap-3">
          <.link
            patch={@patch}
            class="btn btn-outline border-base-content/20 text-base-content/70 hover:bg-base-200/70 hover:border-base-content/30"
          >
            {gettext("Cancel")}
          </.link>
          <.button type="submit" phx-disable-with={gettext("Saving…")} class="btn btn-primary gap-1.5">
            <span class="icon-[tabler--device-floppy] size-4" /> {if @action == :new,
              do: gettext("Create deal"),
              else: gettext("Save changes")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{deal: deal} = assigns, socket) do
    scope = assigns.current_scope
    stages = Deals.list_stages(scope)
    contact_options = build_contact_options(scope, deal)
    owner_options = build_owner_options(scope, deal)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:stages, stages)
     |> assign(:owner_options, owner_options)
     |> assign(:contact_options, contact_options)
     |> assign_new(:submit_attempted?, fn -> false end)
     |> assign_new(:form, fn -> to_form(Deals.change_deal(deal)) end)}
  end

  @impl true
  def handle_event(
        "live_select_change",
        %{"field" => field, "id" => id, "text" => text},
        socket
      ) do
    options = live_select_options(field, socket.assigns.current_scope, text)
    send_update(LiveSelect.Component, id: id, options: options)
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"deal" => params}, socket) do
    changeset =
      Deals.change_deal(socket.assigns.deal, normalize_params(params))

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("save", %{"deal" => params}, socket) do
    save_deal(socket, socket.assigns.action, normalize_params(params))
  end

  defp save_deal(socket, :new, params) do
    case Deals.create_deal(socket.assigns.current_scope, params) do
      {:ok, deal} ->
        send(self(), {:saved, deal})

        {:noreply,
         socket
         |> put_flash(:success, gettext("Deal created"))
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:submit_attempted?, true)
         |> assign(:form, to_form(changeset, action: :validate))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You are not allowed to create deals"))}
    end
  end

  defp save_deal(socket, :edit, params) do
    case Deals.update_deal(socket.assigns.current_scope, socket.assigns.deal, params) do
      {:ok, deal} ->
        send(self(), {:saved, deal})

        {:noreply,
         socket
         |> put_flash(:success, gettext("Deal updated"))
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:submit_attempted?, true)
         |> assign(:form, to_form(changeset, action: :validate))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You are not allowed to update this deal"))}
    end
  end

  defp normalize_params(params) do
    params
    |> Map.update("value", nil, fn
      "" -> nil
      v -> v
    end)
    |> Map.update("probability", nil, fn
      "" -> nil
      v -> v
    end)
    |> Map.update("owner_id", nil, fn
      "" -> nil
      v -> v
    end)
    |> Map.update("source", nil, fn
      "" -> nil
      v -> v
    end)
    |> Map.update("expected_close_date", nil, fn
      "" -> nil
      v -> v
    end)
  end

  defp build_contact_options(scope, deal) do
    base = scope |> Contacts.search_contacts("", 20) |> to_contact_options()

    existing =
      case deal do
        %{contact: %Contacts.Contact{} = c} ->
          %{label: "#{c.first_name} #{c.last_name}", value: c.id}

        %{contact_id: id} when not is_nil(id) ->
          nil

        _ ->
          nil
      end

    if existing && not Enum.any?(base, &(&1.value == existing.value)) do
      [existing | base]
    else
      base
    end
  end

  defp build_contact_search_options(scope, text) do
    scope
    |> Contacts.search_contacts(text, 20)
    |> to_contact_options()
  end

  defp live_select_options("deal_contact_id", scope, text),
    do: build_contact_search_options(scope, text)

  defp live_select_options("deal_owner_id", scope, text),
    do: build_owner_search_options(scope, text)

  defp live_select_options("deal_source", _scope, text), do: filter_source_options(text)

  defp live_select_options("deal_currency", _scope, text), do: filter_currency_options(text)

  defp live_select_options(_field, _scope, _text), do: []

  defp build_owner_options(scope, deal) do
    base = scope.org |> Accounts.list_members() |> to_owner_options()

    existing =
      case deal do
        %{owner: %{email: email, id: id}} -> %{label: email, value: id}
        _ -> nil
      end

    if existing && not Enum.any?(base, &(&1.value == existing.value)) do
      [existing | base]
    else
      base
    end
  end

  defp build_owner_search_options(scope, text) do
    {members, _total} = Accounts.list_members(scope.org, search: text, per_page: 20)
    to_owner_options(members)
  end

  defp to_owner_options(members) do
    Enum.map(members, fn member ->
      %{label: member.user.email, value: member.user_id}
    end)
  end

  defp to_contact_options(contacts) do
    Enum.map(contacts, fn c ->
      label = [c.first_name, c.last_name] |> Enum.filter(&(&1 not in [nil, ""])) |> Enum.join(" ")
      %{label: label, value: c.id}
    end)
  end

  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:label, :string, required: true)
  attr(:myself, :any, required: true)
  attr(:options, :list, default: [])

  defp owner_select(assigns) do
    unassigned = %{label: gettext("— Unassigned"), value: nil}
    assigns = assign(assigns, :live_select_options, [unassigned | assigns.options])

    ~H"""
    <div class="fieldset flex w-full flex-col gap-2">
      <span id={"#{@field.id}-label"} class="label">{@label}</span>
      <div class="group relative w-full">
        <span class="pointer-events-none absolute inset-y-0 left-3 z-20 flex items-center">
          <span class="flex size-6 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
            <.icon name="icon-[tabler--user-check]" class="size-3.5" />
          </span>
        </span>
        <.live_select
          field={@field}
          options={@live_select_options}
          phx-target={@myself}
          value_mapper={&owner_option_value(&1, @live_select_options)}
          placeholder={gettext("Search teammates…")}
          style={:none}
          debounce={150}
          update_min_len={1}
          container_class="relative w-full"
          text_input_class="input h-10 w-full cursor-pointer pl-11 pr-12 font-medium placeholder:text-base-content/40 focus:cursor-text"
          dropdown_class="absolute left-0 top-[calc(100%+4px)] z-[300] max-h-60 w-full overflow-y-auto rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-xl shadow-base-content/10"
          option_class="flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-sm"
          available_option_class="cursor-pointer rounded-md hover:bg-base-200/70"
          selected_option_class="cursor-pointer rounded-md bg-base-200/70 font-semibold"
          active_option_class="bg-base-200"
        >
          <:option :let={opt}>
            <span class="flex size-6 shrink-0 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
              <.icon
                name={
                  if(is_nil(opt.value),
                    do: "icon-[tabler--user-off]",
                    else: "icon-[tabler--user-check]"
                  )
                }
                class="size-3"
              />
            </span>
            <span class={[
              "min-w-0 flex-1 truncate",
              is_nil(opt.value) && "italic text-base-content/40"
            ]}>
              {opt.label}
            </span>
          </:option>
        </.live_select>
        <span
          id={"#{@field.id}-select-chevron"}
          class="pointer-events-none absolute inset-y-0 right-2 z-20 flex items-center text-base-content/45"
        >
          <.icon
            name="icon-[tabler--chevron-down]"
            class="size-4 transition-transform duration-200 group-focus-within:rotate-180"
          />
        </span>
      </div>
    </div>
    """
  end

  defp owner_option_value(value, options) when is_binary(value) do
    case Enum.find(options, &(to_string(&1.value) == value)) do
      nil -> value
      option -> option.value
    end
  end

  defp owner_option_value(value, _options), do: value

  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:myself, :any, required: true)

  defp source_picker(assigns) do
    source_options = source_options()

    selected_source =
      Enum.find(source_options, &(&1.value == to_string(assigns.field.value || "")))

    assigns =
      assigns
      |> assign(:source_options, source_options)
      |> assign(:selected_source, selected_source)
      |> assign(:source_icon, source_icon(selected_source))

    ~H"""
    <div class="fieldset flex w-full flex-col gap-2">
      <span id={"#{@field.id}-label"} class="label">{gettext("Source")}</span>
      <div class="group relative w-full">
        <span class="pointer-events-none absolute inset-y-0 left-3 z-20 flex items-center">
          <span class="flex size-6 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
            <.icon name={@source_icon} class="size-3.5" />
          </span>
        </span>
        <.live_select
          field={@field}
          options={@source_options}
          value={@selected_source || @field.value}
          phx-target={@myself}
          placeholder={gettext("Choose source")}
          style={:none}
          debounce={120}
          update_min_len={0}
          container_class="relative w-full"
          text_input_class="input h-10 w-full cursor-pointer pl-11 pr-12 font-medium placeholder:text-base-content/40 focus:cursor-text"
          dropdown_class="absolute left-0 top-[calc(100%+4px)] z-[300] max-h-60 w-full overflow-y-auto rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-xl shadow-base-content/10"
          option_class="flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-sm"
          available_option_class="cursor-pointer rounded-md hover:bg-base-200/70"
          selected_option_class="cursor-pointer rounded-md bg-base-200/70 font-semibold"
          active_option_class="bg-base-200"
        >
          <:option :let={source}>
            <span class="flex size-6 shrink-0 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
              <.icon name={source.icon} class="size-3" />
            </span>
            <span class={[
              "min-w-0 flex-1 truncate",
              source.value == "" && "italic text-base-content/40"
            ]}>
              {source.label}
            </span>
            <.icon
              :if={source.selected}
              name="icon-[tabler--check]"
              class="size-3.5 shrink-0 text-primary"
            />
          </:option>
        </.live_select>
        <span
          id={"#{@field.id}-select-chevron"}
          class="pointer-events-none absolute inset-y-0 right-2 z-20 flex items-center text-base-content/45"
        >
          <.icon
            name="icon-[tabler--chevron-down]"
            class="size-4 transition-transform duration-200 group-focus-within:rotate-180"
          />
        </span>
      </div>
      <.error :for={msg <- field_errors(@field)}>{msg}</.error>
    </div>
    """
  end

  defp filter_source_options(text) do
    query = text |> to_string() |> String.trim() |> String.downcase()

    Enum.filter(source_options(), fn source ->
      query == "" || String.contains?(String.downcase(source.label), query)
    end)
  end

  defp source_icon(nil), do: "icon-[tabler--tag]"
  defp source_icon(source), do: source.icon

  defp field_errors(field) do
    if Phoenix.Component.used_input?(field) do
      Enum.map(field.errors, &translate_error/1)
    else
      []
    end
  end

  defp source_options do
    [
      %{label: gettext("No source"), value: "", icon: "icon-[tabler--circle-off]"},
      %{label: gettext("Email"), value: "email", icon: "icon-[tabler--mail]"},
      %{label: gettext("Form"), value: "form", icon: "icon-[tabler--forms]"},
      %{label: gettext("Referral"), value: "referral", icon: "icon-[tabler--user-share]"},
      %{label: gettext("Import"), value: "import", icon: "icon-[tabler--file-import]"},
      %{label: gettext("Manual"), value: "manual", icon: "icon-[tabler--pencil]"},
      %{label: gettext("API"), value: "api", icon: "icon-[tabler--braces]"}
    ]
  end

  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:myself, :any, required: true)

  defp currency_picker(assigns) do
    currency_options = currency_options()
    selected_currency = Enum.find(currency_options, &(&1.value == assigns.field.value))

    assigns =
      assigns
      |> assign(:currency_options, currency_options)
      |> assign(:selected_currency, selected_currency)

    ~H"""
    <div class="fieldset flex w-full flex-col gap-2">
      <span id={"#{@field.id}-label"} class="label">{gettext("Currency")}</span>
      <div class="group relative w-full">
        <span class="pointer-events-none absolute inset-y-0 left-3 z-20 flex items-center">
          <span class="flex size-6 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
            <.icon name="icon-[tabler--currency-euro]" class="size-3.5" />
          </span>
        </span>
        <.live_select
          field={@field}
          options={@currency_options}
          value={@selected_currency || @field.value}
          phx-target={@myself}
          placeholder={gettext("Choose currency")}
          style={:none}
          debounce={120}
          update_min_len={0}
          container_class="relative w-full"
          text_input_class="input h-10 w-full cursor-pointer pl-11 pr-12 font-medium placeholder:text-base-content/40 focus:cursor-text"
          dropdown_class="absolute left-0 top-[calc(100%+4px)] z-[300] max-h-60 w-full overflow-y-auto rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-xl shadow-base-content/10"
          option_class="flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-sm"
          available_option_class="cursor-pointer rounded-md hover:bg-base-200/70"
          selected_option_class="cursor-pointer rounded-md bg-base-200/70 font-semibold"
          active_option_class="bg-base-200"
        >
          <:option :let={currency}>
            <span class="flex size-6 shrink-0 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
              <.icon name="icon-[tabler--currency-euro]" class="size-3" />
            </span>
            <span class="min-w-0 flex-1 truncate">{currency.label}</span>
            <.icon
              :if={currency.value == @field.value}
              name="icon-[tabler--check]"
              class="size-3.5 shrink-0 text-primary"
            />
          </:option>
        </.live_select>
        <span
          id={"#{@field.id}-select-chevron"}
          class="pointer-events-none absolute inset-y-0 right-2 z-20 flex items-center text-base-content/45"
        >
          <.icon
            name="icon-[tabler--chevron-down]"
            class="size-4 transition-transform duration-200 group-focus-within:rotate-180"
          />
        </span>
      </div>
      <.error :for={msg <- field_errors(@field)}>{msg}</.error>
    </div>
    """
  end

  defp filter_currency_options(text) do
    query = text |> to_string() |> String.trim() |> String.downcase()

    Enum.filter(currency_options(), fn currency ->
      query == "" || String.contains?(String.downcase(currency.label), query)
    end)
  end

  defp currency_options do
    [
      %{label: "EUR (€)", value: "EUR"},
      %{label: "USD ($)", value: "USD"},
      %{label: "GBP (£)", value: "GBP"}
    ]
  end
end
