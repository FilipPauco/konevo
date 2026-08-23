defmodule KonevoWeb.Plugs.AuthRateLimit do
  @moduledoc """
  Applies rate limits to public HTTP authentication submissions.
  """

  use KonevoWeb, :controller

  alias Konevo.Security.RateLimiter
  alias KonevoWeb.ClientIp

  def init(opts), do: opts

  def call(%{method: "POST", request_path: "/users/log-in"} = conn, _opts) do
    user_params = Map.get(conn.params, "user", %{})

    case Map.get(user_params, "token") do
      token when is_binary(token) and token != "" ->
        check(conn, :magic_link_login, token: token)

      _ ->
        check(conn, :password_login, email: normalized_email(user_params))
    end
  end

  def call(%{method: "POST", request_path: "/users/reset-password"} = conn, _opts) do
    user_params = Map.get(conn.params, "user", %{})
    check(conn, :password_reset, token: Map.get(user_params, "token"))
  end

  def call(%{method: "POST", request_path: "/users/two-factor"} = conn, _opts) do
    challenge = get_session(conn, :pending_two_factor_challenge)

    user_id =
      %{"pending_two_factor_challenge" => challenge}
      |> KonevoWeb.UserAuth.two_factor_challenge_user()
      |> case do
        {:ok, user} -> Integer.to_string(user.id)
        _ -> "invalid"
      end

    check(conn, :two_factor, user_id: user_id)
  end

  def call(conn, _opts), do: conn

  @doc """
  Stores the LiveView peer address for use after mount.
  """
  def assign_client_ip(socket) do
    Phoenix.Component.assign(socket, :auth_rate_limit_client_ip, ClientIp.from_socket(socket))
  end

  @doc """
  Checks a LiveView authentication event using the peer address saved during mount.
  """
  def check_live(socket, bucket, identifiers) do
    RateLimiter.check(bucket, [
      {:ip, Map.get(socket.assigns, :auth_rate_limit_client_ip, "unknown")} | identifiers
    ])
  end

  defp check(conn, bucket, identifiers) do
    case RateLimiter.check(bucket, [{:ip, ClientIp.from_conn(conn)} | identifiers]) do
      :ok ->
        conn

      {:error, retry_after} ->
        rate_limited_response(conn, bucket, retry_after)
    end
  end

  defp rate_limited_response(conn, bucket, retry_after)
       when bucket in [:password_login, :magic_link_login, :two_factor] do
    if html_request?(conn) do
      conn
      |> put_resp_header("retry-after", Integer.to_string(retry_after))
      |> put_flash(:rate_limit_retry_after, Integer.to_string(retry_after))
      |> redirect(to: rate_limit_redirect_path(bucket))
      |> halt()
    else
      too_many_attempts_response(conn, retry_after)
    end
  end

  defp rate_limited_response(conn, _bucket, retry_after) do
    too_many_attempts_response(conn, retry_after)
  end

  defp too_many_attempts_response(conn, retry_after) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(retry_after))
    |> send_resp(429, "Too many attempts. Please try again later.")
    |> halt()
  end

  defp html_request?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, "text/html"))
  end

  defp normalized_email(params) do
    params
    |> Map.get("email", "")
    |> String.trim()
    |> String.downcase()
  end

  defp rate_limit_redirect_path(:two_factor), do: ~p"/users/two-factor"
  defp rate_limit_redirect_path(_bucket), do: ~p"/users/log-in"
end
