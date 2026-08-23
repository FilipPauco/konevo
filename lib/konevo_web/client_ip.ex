defmodule KonevoWeb.ClientIp do
  @moduledoc """
  Resolves client addresses supplied by the trusted Caddy reverse proxy.

  The production Compose deployment does not expose the application container,
  and Caddy overwrites `x-konevo-client-ip` for every upstream request.
  """

  @header "x-konevo-client-ip"
  @unknown "unknown"

  def from_conn(conn) do
    conn
    |> Plug.Conn.get_req_header(@header)
    |> header_ip()
    |> fallback(peer_ip(conn.remote_ip))
  end

  def from_socket(socket) do
    socket
    |> Phoenix.LiveView.get_connect_info(:x_headers)
    |> header_ip()
    |> fallback(socket_peer_ip(socket))
  end

  defp header_ip(headers) when is_list(headers) do
    Enum.find_value(headers, fn
      {@header, value} -> parse_ip(value)
      value when is_binary(value) -> parse_ip(value)
      _value -> nil
    end)
  end

  defp header_ip(_headers), do: nil

  defp socket_peer_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> peer_ip(address)
      _ -> @unknown
    end
  end

  defp parse_ip(value) when is_binary(value) do
    case :inet.parse_address(String.to_charlist(value)) do
      {:ok, address} -> peer_ip(address)
      {:error, _reason} -> nil
    end
  end

  defp parse_ip(_value), do: nil
  defp peer_ip(address) when is_tuple(address), do: address |> :inet.ntoa() |> to_string()
  defp peer_ip(_address), do: @unknown
  defp fallback(nil, value), do: value
  defp fallback(value, _fallback), do: value
end
