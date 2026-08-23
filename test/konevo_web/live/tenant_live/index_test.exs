defmodule KonevoWeb.TenantLive.IndexTest do
  use KonevoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Konevo.AccountsFixtures

  alias Konevo.Accounts
  alias Konevo.Accounts.Scope

  defp org_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}

  setup %{conn: conn} do
    owner = user_fixture()
    public_org = org_fixture(%{name: "Public", slug: "public"})
    {:ok, membership} = Accounts.create_membership(owner, public_org, :owner)

    %{
      conn: log_in_user(conn, owner),
      scope: Scope.for_user_in_org(owner, public_org, membership)
    }
  end

  test "renders the tenant table, search, and add action", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tenants")
    _ = render_async(view)

    assert has_element?(view, "#new-tenant-button")
    assert has_element?(view, "#tenant-search-form")
    assert has_element?(view, "#tenant-table")
  end

  test "searches tenants by organization name", %{conn: conn, scope: scope} do
    slug = unique_org_slug()

    assert {:ok, %{invitation: invitation}} =
             Accounts.create_tenant_invitation(
               scope,
               %{"name" => "Searchable Acme", "slug" => slug, "email" => unique_user_email()},
               fn _organization, token -> "https://#{slug}.example.com/#{token}" end
             )

    {:ok, view, _html} = live(conn, ~p"/tenants")
    _ = render_async(view)

    view
    |> element("#tenant-search-form")
    |> render_submit(%{q: "Searchable Acme"})

    _ = render_async(view)
    assert has_element?(view, "#tenant-invitations tr", "Searchable Acme")
    assert has_element?(view, "#tenant-slug-#{invitation.id}", slug)
    assert has_element?(view, "#tenant-status-#{invitation.id}", "Pending")
    assert has_element?(view, "#tenant-status-#{invitation.id} [class*='clock-hour-4']")

    view
    |> element("[phx-click='archive_tenant'][phx-value-id='#{invitation.id}']")
    |> render_click()

    assert Accounts.get_organization!(invitation.organization_id).archived_at
    assert has_element?(view, "#tenant-status-#{invitation.id}", "Archived")
    assert has_element?(view, "[phx-click='restore_tenant'][phx-value-id='#{invitation.id}']")

    view
    |> element("[phx-click='restore_tenant'][phx-value-id='#{invitation.id}']")
    |> render_click()

    refute Accounts.get_organization!(invitation.organization_id).archived_at
    assert has_element?(view, "[phx-click='archive_tenant'][phx-value-id='#{invitation.id}']")
  end

  test "blocks members from an archived tenant", %{scope: scope} do
    slug = unique_org_slug()
    tenant_owner = user_fixture()

    assert {:ok, %{organization: tenant, invitation: invitation}} =
             Accounts.create_tenant_invitation(
               scope,
               %{"name" => "Archived Acme", "slug" => slug, "email" => tenant_owner.email},
               fn _organization, token -> "https://#{slug}.example.com/#{token}" end
             )

    assert {:ok, _membership} = Accounts.create_membership(tenant_owner, tenant, :owner)
    assert {:ok, _archived_invitation} = Accounts.archive_tenant(scope, invitation.id)

    response =
      build_conn()
      |> log_in_user(tenant_owner)
      |> org_conn(tenant)
      |> get(~p"/dashboard")

    assert html_response(response, 404)
  end
end
