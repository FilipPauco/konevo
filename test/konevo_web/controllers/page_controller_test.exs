defmodule KonevoWeb.PageControllerTest do
  use KonevoWeb.ConnCase

  import Konevo.AccountsFixtures

  test "GET /", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_fragment()

    assert document |> LazyHTML.query("#test-landing") |> Enum.any?()
  end

  test "GET / remains public for a logged-in user outside the host tenant", %{conn: conn} do
    %{user: user} = user_with_org_fixture()
    other_org = org_fixture()

    conn =
      conn
      |> Map.put(:host, "#{other_org.slug}.localhost")
      |> log_in_user(user)
      |> get(~p"/")

    document = conn |> html_response(200) |> LazyHTML.from_fragment()

    assert document |> LazyHTML.query("#test-landing") |> Enum.any?()
  end

  test "GET /dashboard renders the dashboard for a member of the host tenant", %{conn: conn} do
    %{user: user, org: org} = user_with_org_fixture()

    conn =
      conn
      |> Map.put(:host, "#{org.slug}.localhost")
      |> log_in_user(user)
      |> get(~p"/dashboard")

    document = conn |> html_response(200) |> LazyHTML.from_fragment()

    assert document |> LazyHTML.query("#dashboard-loading") |> Enum.any?()
  end

  test "authenticated settings pages return 404 outside the host tenant", %{conn: conn} do
    %{user: user} = user_with_org_fixture()
    other_org = org_fixture()

    conn =
      conn
      |> Map.put(:host, "#{other_org.slug}.localhost")
      |> log_in_user(user)
      |> get(~p"/settings")

    assert html_response(conn, 404)
  end
end
