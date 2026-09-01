defmodule KonevoWeb.HealthController do
  use KonevoWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
