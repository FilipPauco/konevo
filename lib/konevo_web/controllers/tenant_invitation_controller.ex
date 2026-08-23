defmodule KonevoWeb.TenantInvitationController do
  use KonevoWeb, :controller

  alias Konevo.Accounts
  alias KonevoWeb.UserAuth

  def accept(conn, %{"token" => token, "tenant_invitation" => params}) do
    case Accounts.accept_tenant_invitation(token, params) do
      {:ok, %{user: user}} ->
        log_in_or_begin_two_factor_auth(conn, user, params)

      {:error, :invalid_password} ->
        conn
        |> put_flash(:error, gettext("Invalid password"))
        |> redirect(to: ~p"/tenant-invitations/#{token}")

      {:error, :invalid_or_expired} ->
        conn
        |> put_flash(:error, gettext("This invitation link is invalid or has expired"))
        |> redirect(to: ~p"/users/log-in")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, gettext("Please choose a valid password"))
        |> redirect(to: ~p"/tenant-invitations/#{token}")

      {:error, _reason} ->
        conn
        |> put_flash(:error, gettext("Could not accept the invitation. Please try again"))
        |> redirect(to: ~p"/tenant-invitations/#{token}")
    end
  end

  defp log_in_or_begin_two_factor_auth(conn, user, params) do
    if Accounts.two_factor_enabled?(user) do
      conn
      |> put_flash(:info, gettext("Enter the verification code from your authenticator app"))
      |> UserAuth.begin_two_factor_auth(user, params)
    else
      conn
      |> put_flash(:success, gettext("Your workspace is ready"))
      |> UserAuth.log_in_user(user, params)
    end
  end
end
