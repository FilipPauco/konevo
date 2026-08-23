defmodule KonevoWeb.ContactsLive.FormComponent do
  use KonevoWeb, :live_component

  alias Konevo.Companies
  alias Konevo.Contacts
  alias Konevo.Contacts.Contact

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Header --%>
      <div class="mb-6 flex items-center gap-3">
        <div class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary/10">
          <span class={[
            "size-5 text-primary",
            if(@action == :new,
              do: "icon-[tabler--user-plus]",
              else: "icon-[tabler--user-edit]"
            )
          ]} />
        </div>
        <div>
          <h2 class="text-base font-semibold text-base-content">{@title}</h2>
          <p class="text-xs text-base-content/50">
            {if @action == :new,
              do: gettext("Fill in the details to add a new contact"),
              else: gettext("Update the contact information below")}
          </p>
        </div>
      </div>

      <.form
        for={@form}
        id="contact-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <%!-- Name row --%>
        <div class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
          <span class="icon-[tabler--user] size-3.5" />
          {gettext("Basic info")}
        </div>
        <div class="mb-4 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input
              field={@form[:first_name]}
              type="text"
              label={gettext("First name")}
              placeholder="John"
              class="w-full input"
            />
            <.input
              field={@form[:last_name]}
              type="text"
              label={gettext("Last name")}
              placeholder="Doe"
              class="w-full input"
            />
          </div>
          <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input
              field={@form[:email]}
              type="email"
              label={gettext("Email")}
              placeholder="john@example.com"
              class="w-full input"
            />
            <.input
              field={@form[:phone]}
              type="text"
              label={gettext("Phone")}
              placeholder="+1 555 000 0000"
              class="w-full input"
            />
            <.input
              field={@form[:linkedin_url]}
              type="url"
              label={gettext("LinkedIn")}
              placeholder="https://www.linkedin.com/in/jane-doe"
              class="w-full input sm:col-span-2"
            />
          </div>
        </div>

        <%!-- Classification row --%>
        <div class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
          <span class="icon-[tabler--tags] size-3.5" />
          {gettext("Classification")}
        </div>
        <div class="mb-4 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <%!-- Status radio chips --%>
          <div class="fieldset mb-4">
            <div class="flex flex-col gap-2">
              <span class="label">{gettext("Status")}</span>
              <div class="flex flex-wrap gap-2">
                <label :for={{label, value} <- status_options()} class="cursor-pointer">
                  <input
                    type="radio"
                    name={@form[:status].name}
                    value={value}
                    id={"status-opt-#{value}"}
                    class="sr-only peer"
                    checked={to_string(@form[:status].value) == to_string(value)}
                  />
                  <span class={[
                    "inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-sm font-medium transition-all select-none",
                    "border-base-content/20 bg-base-100 text-base-content/60",
                    "peer-checked:font-semibold",
                    status_chip_class(value)
                  ]}>
                    <span class={["size-1.5 rounded-full", status_dot_class(value)]} />
                    {label}
                  </span>
                </label>
              </div>
            </div>
          </div>

          <%!-- Company live search --%>
          <.company_select
            field={@form[:company_id]}
            label={gettext("Company")}
            myself={@myself}
            options={@company_select_options}
          />
        </div>
        <div class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/40">
          <span class="icon-[tabler--notes] size-3.5" />
          {gettext("Notes")}
        </div>
        <div class="mb-6 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <.rich_text_input
            field={@form[:notes]}
            placeholder={gettext("Add any notes about this contact…")}
          />
        </div>

        <%!-- Actions --%>
        <div class="flex justify-end gap-3">
          <button
            :if={@cancel_event}
            type="button"
            phx-click={@cancel_event}
            class="btn btn-outline border-base-content/20 text-base-content/70 hover:bg-base-200/70 hover:border-base-content/30"
          >
            {gettext("Cancel")}
          </button>
          <.link
            :if={!@cancel_event}
            patch={@patch}
            class="btn btn-outline border-base-content/20 text-base-content/70 hover:bg-base-200/70 hover:border-base-content/30"
          >
            {gettext("Cancel")}
          </.link>
          <.button
            phx-disable-with={gettext("Saving…")}
            class="btn btn-primary gap-1.5"
          >
            <span class="icon-[tabler--device-floppy] size-4" />
            {gettext("Save contact")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{contact: contact} = assigns, socket) do
    scope = assigns.current_scope

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:patch, fn -> nil end)
     |> assign_new(:cancel_event, fn -> nil end)
     |> assign_new(:company_select_options, fn ->
       base = scope |> Companies.search_companies("", 20) |> to_company_options()
       # Ensure the existing company (if any) is in the initial options so
       # field.value pre-selection works even when it's outside the top 20.
       existing = resolve_company_option(scope, contact)

       if existing && not Enum.any?(base, &(&1.value == existing.value)) do
         [existing | base]
       else
         base
       end
     end)
     |> assign_new(:form, fn ->
       to_form(Contacts.change_contact(contact))
     end)}
  end

  @impl true
  def handle_event("live_select_change", %{"id" => id, "text" => text}, socket) do
    base =
      socket.assigns.current_scope |> Companies.search_companies(text, 20) |> to_company_options()

    options = [%{label: gettext("No company"), value: nil} | base]
    send_update(LiveSelect.Component, id: id, options: options)
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"contact" => contact_params}, socket) do
    changeset = Contacts.change_contact(socket.assigns.contact, contact_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"contact" => contact_params}, socket) do
    save_contact(socket, socket.assigns.action, contact_params)
  end

  defp save_contact(socket, :edit, contact_params) do
    case Contacts.update_contact(
           socket.assigns.current_scope,
           socket.assigns.contact,
           contact_params
         ) do
      {:ok, contact} ->
        notify_parent({:saved, contact, :updated})

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  defp save_contact(socket, :new, contact_params) do
    case Contacts.create_contact(socket.assigns.current_scope, contact_params) do
      {:ok, contact} ->
        notify_parent({:saved, contact, :created})

        {:noreply, maybe_push_patch(socket, socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  defp status_options do
    Contact.statuses()
    |> Enum.map(fn s -> {Phoenix.Naming.humanize(s), s} end)
  end

  defp status_chip_class(:lead),
    do: "peer-checked:border-info peer-checked:bg-info/15 peer-checked:text-info"

  defp status_chip_class(:prospect),
    do: "peer-checked:border-amber-600 peer-checked:bg-amber-500/10 peer-checked:text-amber-700"

  defp status_chip_class(:customer),
    do: "peer-checked:border-success peer-checked:bg-success/15 peer-checked:text-success"

  defp status_chip_class(:churned),
    do: "peer-checked:border-error peer-checked:bg-error/15 peer-checked:text-error"

  defp status_chip_class(s) when is_binary(s), do: status_chip_class(String.to_existing_atom(s))
  defp status_chip_class(_), do: "border-base-content/20 bg-base-100 text-base-content"

  defp status_dot_class(:lead), do: "bg-info"
  defp status_dot_class(:prospect), do: "bg-warning"
  defp status_dot_class(:customer), do: "bg-success"
  defp status_dot_class(:churned), do: "bg-error"
  defp status_dot_class(s) when is_binary(s), do: status_dot_class(String.to_existing_atom(s))
  defp status_dot_class(_), do: "bg-base-300"

  # Returns a %{label:, value:} map for the existing contact's company so it can
  # be included in the initial options list for field.value pre-selection.
  defp resolve_company_option(_scope, %{company: %Companies.Company{} = c}),
    do: %{label: c.name, value: c.id}

  defp resolve_company_option(scope, %{company_id: id}) when not is_nil(id) do
    c = Companies.get_company!(scope, id)
    %{label: c.name, value: c.id}
  end

  defp resolve_company_option(_scope, _contact), do: nil

  defp to_company_options(companies) do
    Enum.map(companies, fn c -> %{label: c.name, value: c.id} end)
  end

  defp maybe_push_patch(socket, nil), do: socket
  defp maybe_push_patch(socket, patch), do: push_patch(socket, to: patch)

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
