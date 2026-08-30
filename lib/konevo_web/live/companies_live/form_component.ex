defmodule KonevoWeb.CompaniesLive.FormComponent do
  use KonevoWeb, :live_component

  alias Konevo.Companies

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-6 flex items-center gap-3">
        <div class="flex size-10 items-center justify-center rounded-xl bg-primary/10">
          <.icon
            name={
              if @action == :new,
                do: "icon-[tabler--building-plus]",
                else: "icon-[tabler--building-cog]"
            }
            class="size-5 text-primary"
          />
        </div>
        <div>
          <h2 class="font-semibold">{@title}</h2>
          <p class="text-xs text-base-content/50">
            {if @action == :new,
              do: gettext("Add an organization to your CRM"),
              else: gettext("Update company information")}
          </p>
        </div>
      </div>

      <.form
        for={@form}
        id="company-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <section class="mb-4 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <h3 class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/45">
            <.icon name="icon-[tabler--building]" class="size-4" /> {gettext("Company profile")}
          </h3>
          <div class="grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:name]}
              type="text"
              label={gettext("Company name")}
              placeholder="Acme Inc."
              class="input w-full"
            />
            <.input
              field={@form[:industry]}
              type="text"
              label={gettext("Industry")}
              placeholder={gettext("Software, Finance, Retail...")}
              class="input w-full"
            />
            <.input
              field={@form[:website]}
              type="url"
              label={gettext("Website")}
              placeholder="https://example.com"
              class="input w-full"
            />
            <.input
              field={@form[:linkedin_url]}
              type="url"
              label={gettext("LinkedIn")}
              placeholder="https://www.linkedin.com/company/acme"
              class="input w-full"
            />
            <.input
              field={@form[:phone]}
              type="tel"
              label={gettext("Phone")}
              placeholder="+1 555 000 0000"
              class="input w-full"
            />
          </div>
        </section>
        <section class="mb-6 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
          <h3 class="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/45">
            <.icon name="icon-[tabler--notes]" class="size-4" /> {gettext("Notes")}
          </h3>
          <.rich_text_input
            field={@form[:notes]}
            placeholder={gettext("Add context, account details or next steps...")}
          />
        </section>
        <div class="flex justify-end gap-3">
          <.link patch={@patch} class="btn btn-outline">{gettext("Cancel")}</.link>
          <.button phx-disable-with={gettext("Saving…")} class="btn btn-primary gap-1.5">
            <.icon name="icon-[tabler--device-floppy]" class="size-4" /> {gettext("Save company")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{company: company} = assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:form, to_form(Companies.change_company(company)))}
  end

  @impl true
  def handle_event("validate", %{"company" => params}, socket) do
    case authorize(socket) do
      :ok ->
        {:noreply,
         assign(
           socket,
           :form,
           to_form(Companies.change_company(socket.assigns.company, params), action: :validate)
         )}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot change companies"))}
    end
  end

  def handle_event("save", %{"company" => params}, socket) do
    case authorize(socket) do
      :ok ->
        save_company(socket, socket.assigns.action, params)

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot change companies"))}
    end
  end

  defp authorize(%{assigns: %{action: :new, current_scope: scope}}),
    do: Companies.authorize_companies(scope, :create)

  defp authorize(%{assigns: %{current_scope: scope, company: company}}),
    do: Companies.authorize_company(scope, :update, company)

  defp save_company(socket, :edit, params) do
    case Companies.update_company(socket.assigns.current_scope, socket.assigns.company, params) do
      {:ok, company} ->
        notify_parent({:saved, company, :updated})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this company"))}
    end
  end

  defp save_company(socket, :new, params) do
    case Companies.create_company(socket.assigns.current_scope, params) do
      {:ok, company} ->
        notify_parent({:saved, company, :created})
        {:noreply, push_patch(socket, to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot create companies"))}
    end
  end

  defp notify_parent(message), do: send(self(), {__MODULE__, message})
end
