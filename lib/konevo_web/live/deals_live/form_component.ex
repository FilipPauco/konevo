defmodule KonevoWeb.DealsLive.FormComponent do
  use KonevoWeb, :live_component

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
            class="w-full input"
          />
          <%!-- Contact live search --%>
          <.contact_select
            field={@form[:contact_id]}
            myself={@myself}
            label={gettext("Contact")}
            options={@contact_options}
          />
          <%!-- Stage --%>
          <div class="fieldset">
            <label class="label">{gettext("Stage")}</label>
            <div class="flex flex-wrap gap-2">
              <label :for={stage <- @stages} class="cursor-pointer">
                <input
                  type="radio"
                  name={@form[:stage_id].name}
                  value={stage.id}
                  id={"stage-opt-#{stage.id}"}
                  class="sr-only peer"
                  checked={to_string(@form[:stage_id].value) == to_string(stage.id)}
                />
                <span class={[
                  "inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-sm font-medium transition-all select-none cursor-pointer",
                  "border-base-content/20 bg-base-100 text-base-content/60",
                  "peer-checked:border-primary peer-checked:bg-primary/10 peer-checked:text-primary peer-checked:font-semibold"
                ]}>
                  <span
                    class="size-2 rounded-full"
                    style={"background-color: #{stage.color || "#9ca3af"}"}
                  /> {stage.name}
                </span>
              </label>
            </div>

            <.error :for={msg <- Enum.map(@form[:stage_id].errors, &translate_error/1)}>{msg}</.error>
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
                class="w-full input"
              />
            </div>

            <div>
              <.input
                field={@form[:currency]}
                type="select"
                label={gettext("Currency")}
                options={[{"EUR €", "EUR"}, {"USD $", "USD"}, {"GBP £", "GBP"}]}
                class="w-full select"
              />
            </div>
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
              class="w-full input"
            />
            <.input
              field={@form[:source]}
              type="select"
              label={gettext("Source")}
              options={[
                {"—", ""},
                {gettext("Email"), "email"},
                {gettext("Form"), "form"},
                {gettext("Referral"), "referral"},
                {gettext("Import"), "import"},
                {gettext("Manual"), "manual"},
                {gettext("API"), "api"}
              ]}
              class="w-full select"
            />
          </div>
        </div>
        <%!-- Owner --%>
        <div class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
          <span class="icon-[tabler--user-check] size-3.5" /> {gettext("Owner")}
        </div>

        <div class="mb-6 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <.input
            field={@form[:owner_id]}
            type="select"
            label={gettext("Assigned to")}
            options={@owner_options}
            prompt={gettext("— Unassigned")}
            class="w-full select"
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
    members = Accounts.list_members(scope.org)

    owner_options =
      Enum.map(members, fn m ->
        label = m.user.email
        {label, m.user_id}
      end)

    contact_options = build_contact_options(scope, deal)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:stages, stages)
     |> assign(:owner_options, owner_options)
     |> assign(:contact_options, contact_options)
     |> assign_new(:form, fn -> to_form(Deals.change_deal(deal)) end)}
  end

  @impl true
  def handle_event("live_select_change", %{"id" => id, "text" => text}, socket) do
    base = build_contact_search_options(socket.assigns.current_scope, text)
    options = [%{label: gettext("\u2014 No contact \u2014"), value: nil} | base]
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
         |> put_flash(:success, gettext("Deal created successfully"))
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}

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
         |> put_flash(:success, gettext("Deal updated successfully"))
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}

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

  defp to_contact_options(contacts) do
    Enum.map(contacts, fn c ->
      full_name = [c.first_name, c.last_name] |> Enum.filter(&(&1 != "")) |> Enum.join(" ")
      label = if c.email != "", do: "#{full_name} (#{c.email})", else: full_name
      %{label: label, value: c.id}
    end)
  end
end
