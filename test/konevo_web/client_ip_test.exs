defmodule KonevoWeb.ClientIpTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias KonevoWeb.ClientIp

  test "uses the Caddy-injected client address" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("x-konevo-client-ip", "203.0.113.42")

    assert ClientIp.from_conn(conn) == "203.0.113.42"
  end

  test "rejects an invalid proxy header and falls back to the peer address" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("x-konevo-client-ip", "not-an-ip")

    assert ClientIp.from_conn(conn) == "127.0.0.1"
  end

  test "uses the Caddy header for LiveView sockets" do
    socket = %Phoenix.LiveView.Socket{
      private: %{
        connect_info: %{
          x_headers: [{"x-konevo-client-ip", "2001:db8::42"}],
          peer_data: %{address: {127, 0, 0, 1}}
        }
      }
    }

    assert ClientIp.from_socket(socket) == "2001:db8::42"
  end
end
