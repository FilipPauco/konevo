defmodule KonevoWeb.UserSessionControllerTest do
  use KonevoWeb.ConnCase, async: false

  import Konevo.AccountsFixtures
  alias Konevo.Accounts
  alias Konevo.Security.RateLimiter

  setup do
    RateLimiter.reset!()

    on_exit(fn -> RateLimiter.reset!() end)

    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "POST /users/log-in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_konevo_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :success) =~ "Welcome back"
    end

    test "requires and completes two-factor verification", %{conn: conn, user: user} do
      {user, secret} = enable_two_factor(user)
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/users/two-factor"
      refute get_session(conn, :user_token)
      assert get_session(conn, :pending_two_factor_challenge)

      conn =
        post(conn, ~p"/users/two-factor", %{
          "two_factor" => %{"code" => NimbleTOTP.verification_code(secret)}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "rate limits repeated attempts for the same email" do
      params = %{"user" => %{"email" => "rate-limit@example.com", "password" => "invalid"}}

      for _ <- 1..5 do
        conn = post(build_conn(), ~p"/users/log-in", params)
        assert redirected_to(conn) == ~p"/users/log-in"
      end

      conn =
        build_conn()
        |> put_req_header("accept", "text/html")
        |> post(~p"/users/log-in", params)

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_resp_header(conn, "retry-after") != []
      assert Phoenix.Flash.get(conn.assigns.flash, :rate_limit_retry_after) != nil
    end

    test "uses the Caddy client address instead of the proxy peer" do
      for _ <- 1..25 do
        conn =
          build_conn()
          |> put_req_header("x-konevo-client-ip", "203.0.113.10")
          |> post(~p"/users/log-in", %{
            "user" => %{
              "email" => Ecto.UUID.generate() <> "@example.com",
              "password" => "invalid"
            }
          })

        assert redirected_to(conn) == ~p"/users/log-in"
      end

      other_client =
        build_conn()
        |> put_req_header("x-konevo-client-ip", "203.0.113.11")
        |> post(~p"/users/log-in", %{
          "user" => %{"email" => "other-client@example.com", "password" => "invalid"}
        })

      assert redirected_to(other_client) == ~p"/users/log-in"
    end
  end

  describe "POST /users/two-factor" do
    test "rate limits repeated invalid verification codes", %{user: user} do
      {user, _secret} = enable_two_factor(user)

      for _ <- 1..5 do
        conn = begin_two_factor_challenge(user)

        conn =
          post(recycle(conn), ~p"/users/two-factor", %{"two_factor" => %{"code" => "000000"}})

        assert redirected_to(conn) == ~p"/users/two-factor"
      end

      conn =
        user
        |> begin_two_factor_challenge()
        |> recycle()
        |> put_req_header("accept", "text/html")
        |> post(~p"/users/two-factor", %{"two_factor" => %{"code" => "000000"}})

      assert redirected_to(conn) == ~p"/users/two-factor"
      assert get_resp_header(conn, "retry-after") != []
    end
  end

  describe "POST /users/log-in - magic link" do
    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "confirms unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :success) =~ "User confirmed"

      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired"

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/reset-password" do
    test "resets the password and logs the user in", %{conn: conn, user: user} do
      user = set_password(user)
      password = "Updated password!2"

      token =
        extract_user_token(fn url ->
          Accounts.deliver_reset_password_instructions(user, url)
        end)

      conn =
        post(conn, ~p"/users/reset-password", %{
          "user" => %{
            "token" => token,
            "password" => password,
            "password_confirmation" => password
          }
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboard"
      assert Accounts.get_user_by_email_and_password(user.email, password).id == user.id
    end

    test "rejects an invalid reset token", %{conn: conn} do
      conn =
        post(conn, ~p"/users/reset-password", %{
          "user" => %{
            "token" => "invalid",
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        })

      assert redirected_to(conn) == ~p"/users/reset-password"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or it has expired"
    end

    test "rate limits repeated reset attempts for the same token" do
      params = %{
        "user" => %{
          "token" => "invalid-reset-token",
          "password" => valid_user_password(),
          "password_confirmation" => valid_user_password()
        }
      }

      for _ <- 1..5 do
        conn = post(build_conn(), ~p"/users/reset-password", params)
        assert redirected_to(conn) == ~p"/users/reset-password"
      end

      conn = post(build_conn(), ~p"/users/reset-password", params)

      assert conn.status == 429
      assert get_resp_header(conn, "retry-after") != []
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :success) =~ "Logged out"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :success) =~ "Logged out"
    end
  end

  defp enable_two_factor(user) do
    secret = Accounts.new_two_factor_secret()
    code = NimbleTOTP.verification_code(secret)
    {:ok, user} = Accounts.enable_two_factor(user, secret, code)

    user =
      user
      |> Ecto.Changeset.change(
        two_factor_last_used_at:
          DateTime.utc_now() |> DateTime.add(-31, :second) |> DateTime.truncate(:second)
      )
      |> Konevo.Repo.update!()

    {user, secret}
  end

  defp begin_two_factor_challenge(user) do
    build_conn()
    |> init_test_session(%{})
    |> KonevoWeb.UserAuth.begin_two_factor_auth(user)
  end
end
