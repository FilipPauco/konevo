defmodule KonevoWeb.SupportLiveTest do
  use KonevoWeb.ConnCase, async: false

  describe "support route" do
    setup :register_and_log_in_user_with_org

    test "is unavailable while disabled", %{conn: conn, org: org} do
      conn = conn |> org_conn(org) |> get("/support")

      assert conn.status == 404
    end
  end

  defp org_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}
end
