defmodule KonevoWeb.UserLive.PasswordReset do
  use KonevoWeb, :live_view

  alias Konevo.Accounts
  alias Konevo.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth
      flash={@flash}
      current_scope={@current_scope}
      variant={:immersive}
      brand_placement={:inside}
    >
      <Layouts.auth_card id="password-reset">
        <Layouts.auth_brand />
        <Layouts.auth_header
          title={gettext("Choose a new password")}
          subtitle={gettext("Use a strong password you don't use elsewhere.")}
        />

        <.form
          for={@form}
          id="password-reset-form"
          action={~p"/users/reset-password"}
          phx-submit="save"
          phx-change="validate"
          phx-trigger-action={@trigger_submit}
          class="space-y-4"
        >
          <.input field={@form[:token]} type="hidden" />
          <.input
            field={@form[:password]}
            type="password"
            label={gettext("New password")}
            placeholder={gettext("Create a new password")}
            autocomplete="new-password"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label={gettext("Confirm new password")}
            placeholder={gettext("Re-enter your new password")}
            autocomplete="new-password"
            required
          />
          <p class="text-xs leading-5 text-base-content/55">
            {gettext("Use 6–35 characters with uppercase, lowercase, and a number or symbol.")}
          </p>
          <.button class="btn btn-primary w-full" type="submit">
            {gettext("Reset password")}
          </.button>
        </.form>
      </Layouts.auth_card>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    form = password_form(token)

    if connected?(socket) do
      case Accounts.get_user_by_reset_password_token(token) do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, gettext("Password reset link is invalid or it has expired"))
           |> push_navigate(to: ~p"/users/reset-password")}

        _user ->
          {:ok, assign(socket, form: form, trigger_submit: false)}
      end
    else
      {:ok, assign(socket, form: form, trigger_submit: false)}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: password_form(params, validate?: true))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    form = password_form(params, validate?: true)

    if password_changeset(params).valid? do
      {:noreply, assign(socket, form: form, trigger_submit: true)}
    else
      {:noreply, assign(socket, form: form)}
    end
  end

  defp password_form(token) when is_binary(token) do
    to_form(%{"token" => token, "password" => "", "password_confirmation" => ""}, as: "user")
  end

  defp password_form(params, validate?: true) do
    errors =
      params
      |> password_changeset()
      |> Ecto.Changeset.traverse_errors(&translate_error/1)
      |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &{field, {&1, []}}) end)

    to_form(params, as: "user", errors: errors)
  end

  defp password_changeset(params) do
    %User{}
    |> User.password_changeset(params, hash_password: false)
    |> Map.put(:action, :validate)
  end
end
