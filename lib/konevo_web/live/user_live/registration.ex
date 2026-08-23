defmodule KonevoWeb.UserLive.Registration do
  use KonevoWeb, :live_view

  alias Konevo.Accounts
  alias Konevo.Accounts.User
  alias KonevoWeb.Plugs.AuthRateLimit
  alias KonevoWeb.Plugs.LoadOrganization

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth
      flash={@flash}
      current_scope={@current_scope}
      variant={:immersive}
      brand_placement={:inside}
    >
      <section
        id="registration-workspace"
        class="mx-auto w-full max-w-md space-y-2 rounded-2xl border border-secondary/35 bg-base-100/95 p-6 shadow-2xl shadow-base-content/10 backdrop-blur sm:p-8"
      >
        <Layouts.auth_brand />
        <div class="text-center">
          <h1 class="text-2xl font-semibold tracking-tight text-base-content sm:text-3xl">
            {gettext("Create your account")}
          </h1>
          <p class="mt-2 text-center text-sm leading-6 text-base-content/65">
            {gettext("Already registered?")}
            <.link
              navigate={~p"/users/log-in"}
              class="ml-1 font-semibold text-primary transition-colors hover:text-primary/75 hover:underline"
            >
              {gettext("Log in")}
            </.link>
          </p>
        </div>

        <.form
          for={@form}
          id="registration_form"
          action={~p"/users/log-in"}
          phx-submit="save"
          phx-change="validate"
          phx-trigger-action={@trigger_submit}
          class="space-y-4"
        >
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            placeholder={gettext("Enter your email address")}
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            label={gettext("Password")}
            placeholder={gettext("Create a password")}
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label={gettext("Confirm password")}
            placeholder={gettext("Re-enter your password")}
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <p class="text-xs leading-5 text-base-content/55">
            {gettext("Use 6–35 characters with uppercase, lowercase, and a number or symbol.")}
          </p>

          <.button
            phx-disable-with={gettext("Creating account...")}
            class="btn btn-primary w-full"
            type="submit"
          >
            {gettext("Create account")}
          </.button>
        </.form>
      </section>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: KonevoWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    slug = LoadOrganization.extract_slug(socket.host_uri && socket.host_uri.host)

    {:ok,
     socket
     |> AuthRateLimit.assign_client_ip()
     |> assign(
       form:
         to_form(%{"email" => "", "password" => "", "password_confirmation" => ""}, as: "user"),
       org_slug: slug,
       workspace_from_host?: not is_nil(slug),
       trigger_submit: false
     )}
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    case AuthRateLimit.check_live(socket, :registration, email: normalized_email(params)) do
      :ok ->
        register(socket, params)

      {:error, _retry_after} ->
        {:noreply,
         put_flash(socket, :error, gettext("Too many attempts. Please try again later."))}
    end
  end

  def handle_event("validate", %{"user" => params}, socket) do
    errors = params |> user_changeset() |> form_errors()

    {:noreply, assign(socket, form: to_form(params, as: "user", errors: errors))}
  end

  defp register(socket, params) do
    case register_user(params, socket.assigns) do
      {:ok, %{user: _user}} ->
        {:noreply,
         socket
         |> put_flash(:success, gettext("Account created successfully"))
         |> assign(:trigger_submit, true)}

      {:error, :user, %Ecto.Changeset{} = changeset, _changes} ->
        {:noreply,
         assign(socket, form: to_form(params, as: "user", errors: form_errors(changeset)))}

      {:error, :org, %Ecto.Changeset{}, _changes} ->
        if socket.assigns.workspace_from_host? do
          {:noreply,
           put_flash(socket, :error, gettext("This workspace is unavailable. Please try another"))}
        else
          {:noreply, put_flash(socket, :error, gettext("The default workspace is unavailable"))}
        end

      {:error, :org, :not_found, _changes} ->
        {:noreply, put_flash(socket, :error, gettext("The default workspace is unavailable"))}

      {:error, _op, _reason, _changes} ->
        {:noreply, put_flash(socket, :error, gettext("Something went wrong. Please try again"))}
    end
  end

  defp register_user(params, %{workspace_from_host?: true, org_slug: slug}) do
    Accounts.register_password_user_with_org(
      Map.merge(params, %{"org_name" => org_name_from_slug(slug), "org_slug" => slug})
    )
  end

  defp register_user(params, _assigns) do
    Accounts.register_password_user_with_default_org(params)
  end

  defp user_changeset(params) do
    %User{}
    |> User.email_changeset(params, validate_unique: false)
    |> User.password_changeset(params, hash_password: false)
    |> Map.put(:action, :validate)
  end

  defp form_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &{field, {&1, []}}) end)
  end

  defp org_name_from_slug(slug) do
    slug
    |> String.replace("-", " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp normalized_email(params) do
    params
    |> Map.get("email", "")
    |> String.trim()
    |> String.downcase()
  end
end
