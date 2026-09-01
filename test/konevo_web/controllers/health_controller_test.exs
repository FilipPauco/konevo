defmodule KonevoWeb.HealthControllerTest do
  use KonevoWeb.ConnCase, async: true

  test "GET /health returns the public health response", %{conn: conn} do
    assert conn |> get("/health") |> json_response(200) == %{"status" => "ok"}
  end
end
