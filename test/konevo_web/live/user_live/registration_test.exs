defmodule KonevoWeb.UserLive.RegistrationTest do
  use KonevoWeb.ConnCase, async: true

  test "public registration is not routed", %{conn: conn} do
    assert conn |> get("/users/register") |> html_response(404)
  end
end
