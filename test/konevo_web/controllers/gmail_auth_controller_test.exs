defmodule KonevoWeb.GmailAuthControllerTest do
  use KonevoWeb.ConnCase, async: true

  setup :register_and_log_in_user_with_org

  test "shows the Gmail data-use notice before connecting", %{conn: conn, org: org} do
    conn = org_conn(conn, org)

    html = conn |> get("/integrations/gmail/consent") |> html_response(200)

    assert html =~ "How Konevo will use your Gmail data"
    assert html =~ "Continue to Google"
  end

  test "requires acknowledgement before starting Gmail OAuth", %{conn: conn, org: org} do
    conn = org_conn(conn, org)

    assert conn |> get("/integrations/gmail/connect") |> redirected_to() ==
             "/integrations/gmail/consent"

    conn = post(conn, "/integrations/gmail/consent", %{"gmail" => %{}})

    assert redirected_to(conn) == "/integrations/gmail/consent"
  end

  test "records acknowledgement before continuing to Gmail OAuth", %{conn: conn, org: org} do
    conn = org_conn(conn, org)

    conn = post(conn, "/integrations/gmail/consent", %{"gmail" => %{"acknowledged" => "true"}})

    assert redirected_to(conn) == "/integrations/gmail/connect"
  end

  defp org_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}
end
