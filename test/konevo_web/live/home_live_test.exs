defmodule KonevoWeb.HomeLiveTest do
  use KonevoWeb.ConnCase

  import Phoenix.LiveViewTest
  import Konevo.AccountsFixtures

  describe "authenticated dashboard" do
    test "renders the operational dashboard for a workspace member", %{conn: conn} do
      %{user: user, org: org} = user_with_org_fixture()

      conn =
        conn
        |> Map.put(:host, "#{org.slug}.localhost")
        |> log_in_user(user)

      {:ok, view, html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#dashboard-loading[aria-busy='true']")
      assert has_element?(view, "#dashboard-brief-skeleton")
      assert has_element?(view, "#dashboard-action-queue-skeleton")
      assert has_element?(view, "#dashboard-follow-up-radar-skeleton")
      assert has_element?(view, "#dashboard-pipeline-risk-skeleton")
      assert has_element?(view, "#dashboard-task-commitments-skeleton")
      assert html =~ "href=\"/dashboard\""
      assert html =~ "aria-current=\"page\""

      html = render_async(view, 5_000)

      assert html =~ "Dashboard"
      assert html =~ "Daily owner brief"
      assert html =~ "Today&#39;s action queue"
      assert html =~ "Follow-up radar"
      assert html =~ "Pipeline risk"
      assert html =~ "Task commitments"
    end
  end
end
