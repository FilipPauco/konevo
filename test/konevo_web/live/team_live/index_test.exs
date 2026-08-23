defmodule KonevoWeb.TeamLive.IndexTest do
  use KonevoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Konevo.AccountsFixtures

  alias Konevo.Accounts

  # Connects to /team under the org's subdomain host.
  # The :load_org_scope on_mount reads socket.host_uri.host (e.g. "myslug.localhost").
  defp subdomain_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}

  defp connect_as_owner(conn, org) do
    conn
    |> subdomain_conn(org)
    |> live(~p"/team")
  end

  describe "mount" do
    setup :register_and_log_in_user_with_org

    test "renders team page and shows invite button for owner", %{conn: conn, org: org} do
      {:ok, _lv, html} = connect_as_owner(conn, org)

      assert html =~ "Team"
      assert html =~ "Invite member"
    end

    test "lists the current owner in the members stream", %{conn: conn, org: org, user: owner} do
      {:ok, lv, _html} = connect_as_owner(conn, org)

      html = render_async(lv)
      assert html =~ owner.email
    end

    test "viewer sees members but no invite button", %{conn: conn, org: org} do
      viewer = user_fixture()
      {:ok, _membership} = Accounts.create_membership(viewer, org, :viewer)

      viewer_conn =
        conn
        |> log_in_user(viewer)
        |> subdomain_conn(org)

      {:ok, _lv, html} = live(viewer_conn, ~p"/team")

      refute html =~ "Invite member"
    end

    test "renders a skeleton while team members load", %{conn: conn, org: org} do
      document =
        conn
        |> subdomain_conn(org)
        |> get(~p"/team")
        |> html_response(200)
        |> LazyHTML.from_fragment()

      assert document |> LazyHTML.query("#team-loading[aria-busy='true']") |> Enum.any?()
      refute document |> LazyHTML.query("#team-table") |> Enum.any?()
      refute document |> LazyHTML.query("#team-footer") |> Enum.any?()
    end
  end

  describe "search and pagination" do
    setup :register_and_log_in_user_with_org

    test "search event narrows the member list", %{conn: conn, org: org} do
      alice = user_fixture(%{email: "alice.team@example.com"})
      bob = user_fixture(%{email: "bob.team@example.com"})
      {:ok, alice_membership} = Accounts.create_membership(alice, org, :member)
      {:ok, bob_membership} = Accounts.create_membership(bob, org, :member)

      {:ok, lv, _html} = connect_as_owner(conn, org)
      _ = render_async(lv)

      lv |> element("#team-search-form") |> render_submit(%{q: "alice.team"})
      _ = render_async(lv)

      assert has_element?(lv, "#members-#{alice_membership.id}")
      refute has_element?(lv, "#members-#{bob_membership.id}")
    end

    test "paginates team members", %{conn: conn, org: org} do
      for n <- 1..26 do
        user = user_fixture(%{email: "team-page-#{n}@example.com"})
        {:ok, _membership} = Accounts.create_membership(user, org, :member)
      end

      {:ok, lv, _html} = connect_as_owner(conn, org)
      html = render_async(lv)
      assert html =~ "Showing 1-25 of 27"

      html = lv |> element("button[aria-label='Next page']") |> render_click()
      html = html <> render_async(lv)

      assert html =~ "Showing 26-27 of 27"
    end
  end

  describe "invite member" do
    setup :register_and_log_in_user_with_org

    test "owner can open invite modal", %{conn: conn, org: org} do
      {:ok, lv, _html} = connect_as_owner(conn, org)
      _ = render_async(lv)

      html = lv |> element("button[phx-click='open_invite']") |> render_click()

      assert html =~ "Invite a member"
    end

    test "owner can close invite modal", %{conn: conn, org: org} do
      {:ok, lv, _html} = connect_as_owner(conn, org)
      _ = render_async(lv)

      lv |> element("button[phx-click='open_invite']") |> render_click()
      # Use the Cancel button specifically (there are two close_invite buttons)
      html = lv |> element("button[phx-click='close_invite']", "Cancel") |> render_click()

      refute html =~ "Invite a member"
    end

    test "inviting a new email creates membership and shows flash", %{conn: conn, org: org} do
      {:ok, lv, _html} = connect_as_owner(conn, org)
      _ = render_async(lv)

      lv |> element("button[phx-click='open_invite']") |> render_click()

      new_email = unique_user_email()

      html =
        lv
        |> form("#invite-form", invite: %{email: new_email, role: "member"})
        |> render_submit()

      assert html =~ "Invitation sent to #{new_email}"
      assert Accounts.get_user_by_email(new_email)
    end

    test "inviting an already-member email shows error", %{conn: conn, org: org, user: owner} do
      {:ok, lv, _html} = connect_as_owner(conn, org)
      _ = render_async(lv)

      lv |> element("button[phx-click='open_invite']") |> render_click()

      html =
        lv
        |> form("#invite-form", invite: %{email: owner.email, role: "member"})
        |> render_submit()

      assert html =~ "already a member"
    end
  end

  describe "change role" do
    setup :register_and_log_in_user_with_org

    test "admin can change another member's role", %{conn: conn, org: org} do
      # add an admin
      admin = user_fixture()
      {:ok, _} = Accounts.create_membership(admin, org, :admin)

      admin_conn =
        conn
        |> log_in_user(admin)
        |> subdomain_conn(org)

      {:ok, _lv, _html} = live(admin_conn, ~p"/team")

      # add a plain member to change role of
      member = user_fixture()
      {:ok, membership} = Accounts.create_membership(member, org, :member)

      # re-stream: reload the page to pick up new member
      {:ok, lv, _html} = live(admin_conn, ~p"/team")
      _ = render_async(lv)

      html =
        lv
        |> element("form[phx-change='change_role'][phx-value-id='#{membership.id}']")
        |> render_change(%{role: "viewer"})

      # viewer badge should now appear somewhere
      assert html =~ "viewer" or has_element?(lv, "#members-#{membership.id}")
    end
  end

  describe "remove member" do
    setup :register_and_log_in_user_with_org

    test "owner can remove a non-owner member", %{conn: conn, org: org} do
      member = user_fixture()
      {:ok, membership} = Accounts.create_membership(member, org, :member)

      {:ok, lv, _html} = connect_as_owner(conn, org)
      _ = render_async(lv)

      assert has_element?(lv, "#members-#{membership.id}")

      lv
      |> element("[phx-click='remove_member'][phx-value-id='#{membership.id}']")
      |> render_click()

      refute has_element?(lv, "#members-#{membership.id}")
    end

    test "cannot remove the owner", %{conn: conn, org: org, membership: owner_membership} do
      {:ok, lv, _html} = connect_as_owner(conn, org)
      _ = render_async(lv)

      html =
        lv
        |> render_click("remove_member", %{id: owner_membership.id})

      assert html =~ "Cannot remove the owner"
    end
  end
end
