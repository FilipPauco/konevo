defmodule KonevoWeb.UserSessionController do
  use KonevoWeb, :controller

  alias Konevo.Accounts
  alias KonevoWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, gettext("User confirmed successfully"))
  end

  def create(conn, params) do
    create(conn, params, gettext("Welcome back"))
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> log_in_or_begin_two_factor_auth(user, user_params, info)

      _ ->
        conn
        |> put_flash(:error, gettext("The link is invalid or it has expired"))
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> log_in_or_begin_two_factor_auth(user, user_params, info)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, gettext("Invalid email or password"))
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/settings")
    |> create(params, gettext("Password updated successfully"))
  end

  def reset_password(conn, %{"user" => %{"token" => token} = user_params}) do
    case Accounts.reset_user_password(token, user_params) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> log_in_or_begin_two_factor_auth(
          user,
          user_params,
          gettext("Password reset successfully")
        )

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, gettext("Password reset link is invalid or it has expired"))
        |> redirect(to: ~p"/users/reset-password")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, gettext("Please choose a valid password"))
        |> redirect(to: ~p"/users/reset-password/#{token}")
    end
  end

  def two_factor(conn, %{"two_factor" => %{"code" => code}}) do
    with {:ok, user} <-
           UserAuth.two_factor_challenge_user(
             get_session(conn, :pending_two_factor_challenge)
             |> two_factor_session()
           ),
         {:ok, user} <- Accounts.verify_two_factor_code(user, code) do
      params = %{
        "remember_me" =>
          if(get_session(conn, :pending_two_factor_remember_me), do: "true", else: "false")
      }

      conn
      |> put_flash(:success, gettext("Welcome back"))
      |> UserAuth.log_in_user(user, params)
    else
      _ ->
        conn
        |> put_flash(:error, gettext("Invalid verification code"))
        |> redirect(to: ~p"/users/two-factor")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:success, gettext("Logged out successfully"))
    |> UserAuth.log_out_user()
  end

  defp log_in_or_begin_two_factor_auth(conn, user, user_params, info) do
    if Accounts.two_factor_enabled?(user) do
      conn
      |> put_flash(:info, gettext("Enter the verification code from your authenticator app"))
      |> UserAuth.begin_two_factor_auth(user, user_params)
    else
      conn
      |> put_flash(:success, info)
      |> UserAuth.log_in_user(user, user_params)
    end
  end

  defp two_factor_session(challenge), do: %{"pending_two_factor_challenge" => challenge}
end
