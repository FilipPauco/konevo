defmodule KonevoWeb.Nav do
  @moduledoc """
  LiveView on_mount hook that assigns the current request path to the socket,
  enabling navigation highlighting in the sidebar layout.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     attach_hook(socket, :set_current_path, :handle_params, fn _params, url, socket ->
       {:cont, assign(socket, :current_path, URI.parse(url).path)}
     end)}
  end
end
