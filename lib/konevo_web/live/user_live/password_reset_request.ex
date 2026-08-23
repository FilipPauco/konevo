defmodule KonevoWeb.UserLive.PasswordResetRequest do
  use KonevoWeb, :live_view

  require Logger

  alias Konevo.Accounts
  alias KonevoWeb.Plugs.AuthRateLimit

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth
      flash={@flash}
      current_scope={@current_scope}
      variant={:immersive}
      brand_placement={:inside}
    >
      <Layouts.auth_card id="password-reset-request">
        <Layouts.auth_brand />
        <Layouts.auth_header
          title={gettext("Reset your password")}
          subtitle={gettext("Enter your email and we'll send a secure password reset link.")}
        />

        <.form for={@form} id="password-reset-request-form" phx-submit="submit">
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
          <div class="mt-6 space-y-3">
            <.button class="btn btn-primary w-full" type="submit">
              {gettext("Send reset link")}
            </.button>

            <p class="text-center text-sm text-base-content/65">
              {gettext("Remembered your password?")}
              <.link
                navigate={~p"/users/log-in"}
                class="ml-1 font-semibold text-primary transition-colors hover:text-primary/75 hover:underline"
              >
                {gettext("Sign in")}
              </.link>
            </p>
          </div>
        </.form>
      </Layouts.auth_card>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> AuthRateLimit.assign_client_ip()
     |> assign(form: to_form(%{"email" => ""}, as: "user"))}
  end

  @impl true
  def handle_event("submit", %{"user" => %{"email" => email}}, socket) do
    case AuthRateLimit.check_live(socket, :password_reset_request, email: normalized_email(email)) do
      :ok ->
        deliver_reset_instructions(socket, email)

      {:error, _retry_after} ->
        {:noreply,
         put_flash(socket, :error, gettext("Too many attempts. Please try again later."))}
    end
  end

  defp deliver_reset_instructions(socket, email) do
    case Accounts.get_user_by_email(email) do
      nil ->
        :ok

      user ->
        deliver_reset_email(user, socket)
    end

    {:noreply,
     socket
     |> put_flash(
       :info,
       gettext("If an account exists for that email, you will receive reset instructions shortly")
     )
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp reset_url(socket, token) do
    uri = socket.host_uri || URI.parse(KonevoWeb.Endpoint.url())
    port = if uri.port in [80, 443, nil], do: "", else: ":#{uri.port}"
    "#{uri.scheme}://#{uri.host}#{port}/users/reset-password/#{token}"
  end

  defp deliver_reset_email(user, socket) do
    case Accounts.deliver_reset_password_instructions(user, &reset_url(socket, &1)) do
      {:ok, _email} -> :ok
      {:error, reason} -> Logger.warning("password reset email failed: #{inspect(reason)}")
    end
  end

  defp normalized_email(email), do: email |> String.trim() |> String.downcase()
end
