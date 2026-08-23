defmodule KonevoWeb.UserLive.LoginTest do
  use KonevoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Konevo.AccountsFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Welcome back"
      assert html =~ "Sign in to your private Konevo workspace."
      refute html =~ "Sign up"
      assert has_element?(lv, "#auth-brand[href='/'] img[alt='Konevo']")
      assert has_element?(lv, "a[href='/users/reset-password']")
      refute has_element?(lv, "#google-sign-in")
      refute has_element?(lv, "#login-source-code-link")
    end

    test "shows a retry countdown when rate limited", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> Phoenix.Controller.put_flash(:rate_limit_retry_after, "900")

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      assert has_element?(lv, "#login-rate-limit[data-retry-after='900']")
      assert has_element?(lv, "#login-submit-button[disabled]")
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows the re-authentication form", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "You need to reauthenticate"
      refute html =~ "Register"
      assert html =~ "Sign in"
      assert has_element?(lv, "#user_email")
    end
  end
end
