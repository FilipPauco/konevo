defmodule KonevoWeb.UserLive.PasswordResetRequestTest do
  use KonevoWeb.ConnCase, async: false

  import Konevo.AccountsFixtures
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Konevo.Security.RateLimiter

  setup do
    :ok = set_swoosh_global()
    RateLimiter.reset!()

    on_exit(fn -> RateLimiter.reset!() end)
  end

  test "sends a reset link for an existing account", %{conn: conn} do
    user = user_fixture() |> set_password()
    {:ok, view, _html} = live(conn, ~p"/users/reset-password")

    view
    |> form("#password-reset-request-form", user: %{email: user.email})
    |> render_submit()

    assert_redirect(view, ~p"/users/log-in")

    assert_email_sent(fn email ->
      email.subject == "Reset your password" and
        Enum.any?(email.to, fn {_name, address} -> address == user.email end) and
        email.text_body =~ "/users/reset-password/"
    end)
  end
end
