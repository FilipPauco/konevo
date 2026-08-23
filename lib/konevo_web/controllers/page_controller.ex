defmodule KonevoWeb.PageController do
  use KonevoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
