defmodule KonevoWeb.CompaniesLive.IndexTest do
  use KonevoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Konevo.Factory
  import Konevo.CompaniesFixtures

  alias Konevo.Accounts.Scope
  alias Konevo.Companies

  setup do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: :owner)
    scope = Scope.for_user_in_org(user, org, membership)
    conn = build_conn() |> log_in_user(user) |> org_conn(org)
    %{conn: conn, org: org, scope: scope, user: user}
  end

  test "silently redirects unauthenticated users home", %{org: org} do
    {:error, {:redirect, %{to: path}}} = live(org_conn(build_conn(), org), ~p"/companies")
    assert path == "/"
  end

  test "renders table, filters and footer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/companies")
    _html = render_async(view)
    assert has_element?(view, "#company-search-form")
    assert has_element?(view, "#companies-table")
    assert has_element?(view, "#companies-empty")
    refute has_element?(view, "#companies-footer")
  end

  test "uses the card surface when cards are selected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/companies")
    _ = render_async(view)
    view |> element("#companies-view-cards") |> render_click()

    assert has_element?(view, "#companies-cards-empty.bg-base-100")
  end

  test "lists only tenant companies and filters by search", %{conn: conn, scope: scope} do
    acme = company_fixture(scope, %{name: "Acme Labs"})
    northwind = company_fixture(scope, %{name: "Northwind"})
    {:ok, view, _html} = live(conn, ~p"/companies")
    _html = render_async(view)

    view |> form("#company-search-form", q: "Acme") |> render_change()
    _html = render_async(view)

    assert has_element?(view, "#companies a[href^='/companies/#{acme.slug}']")
    refute has_element?(view, "#companies a[href^='/companies/#{northwind.slug}']")
    assert has_element?(view, "#companies-clear-filters")
    assert has_element?(view, "#companies-filter-panel #companies-clear-filters")
    assert has_element?(view, "#companies-archive-filter-mobile")

    view |> element("#companies-clear-filters") |> render_click()
    _html = render_async(view)

    assert has_element?(view, "#companies a[href^='/companies/#{northwind.slug}']")
    refute has_element?(view, "#companies-clear-filters")
  end

  test "shows LinkedIn icon in cards when company has a LinkedIn URL", %{
    conn: conn,
    scope: scope,
    user: _user
  } do
    linkedin_url = "https://www.linkedin.com/company/card-company"
    company = company_fixture(scope, %{linkedin_url: linkedin_url})
    {:ok, view, _html} = live(conn, ~p"/companies")
    _html = render_async(view)
    view |> element("#companies-view-cards") |> render_click()
    _html = render_async(view)

    assert has_element?(
             view,
             ~s(#companies-cards #company-card-linkedin-#{company.id}[href="#{linkedin_url}"])
           )
  end

  test "hides LinkedIn icon in cards when company LinkedIn URL is blank", %{
    conn: conn,
    scope: scope,
    user: _user
  } do
    company = company_fixture(scope, %{linkedin_url: "  "})
    {:ok, view, _html} = live(conn, ~p"/companies")
    _html = render_async(view)
    view |> element("#companies-view-cards") |> render_click()

    refute has_element?(view, "#companies-cards #company-card-linkedin-#{company.id}")
  end

  test "creates, edits and deletes a company", %{conn: conn, scope: scope} do
    {:ok, create_view, _html} = live(conn, ~p"/companies/new")
    _html = render_async(create_view)
    assert has_element?(create_view, "#company-form input[name='company[linkedin_url]']")

    create_view
    |> form("#company-form",
      company: %{
        name: "Created Co",
        linkedin_url: "https://www.linkedin.com/company/created-co"
      }
    )
    |> render_submit()

    _ = :sys.get_state(create_view.pid)
    assert render_async(create_view, 1_000) =~ "Created Co"

    company = company_fixture(scope, %{name: "Editable Co"})
    {:ok, edit_view, _html} = live(conn, ~p"/companies/#{company.id}/edit/inline")
    _html = render_async(edit_view)
    assert has_element?(edit_view, "#company-form input[name='company[linkedin_url]']")

    edit_view |> form("#company-form", company: %{name: "Updated Co"}) |> render_submit()
    _ = :sys.get_state(edit_view.pid)
    assert render_async(edit_view, 1_000) =~ "Updated Co"

    edit_view
    |> element("[phx-click='delete'][phx-value-id='#{company.id}']")
    |> render_click()

    refute has_element?(edit_view, "[phx-value-id='#{company.id}']")
    assert has_element?(edit_view, "#flash-success", "Company deleted")
  end

  test "preserves filters when editing a company", %{conn: conn, scope: scope} do
    company = company_fixture(scope, %{name: "Filtered edit"})
    {:ok, _company} = Companies.archive_company(scope, company)

    {:ok, view, _html} = live(conn, ~p"/companies?archived=archived")
    _ = render_async(view)

    view
    |> element("a[href='/companies/#{company.slug}/edit/inline?archived=archived']")
    |> render_click()

    assert_patch(view, ~p"/companies/#{company}/edit/inline?archived=archived")

    view
    |> form("#company-form", company: %{name: "Filtered update"})
    |> render_submit()

    assert_patch(view, ~p"/companies?archived=archived")
  end

  test "filters companies by industry", %{conn: conn, scope: scope} do
    software = company_fixture(scope, %{name: "Software Co", industry: "Software"})
    finance = company_fixture(scope, %{name: "Finance Co", industry: "Finance"})

    {:ok, view, _html} = live(conn, ~p"/companies")
    _html = render_async(view)

    view
    |> element("#industry-filter-dropdown input[phx-value-industry='Software']")
    |> render_click()

    _html = render_async(view)

    assert has_element?(view, "#companies a[href^='/companies/#{software.slug}']")
    refute has_element?(view, "#companies a[href^='/companies/#{finance.slug}']")
  end

  test "archives and restores a company from the list", %{conn: conn, scope: scope} do
    company = company_fixture(scope, %{name: "Archive Co"})

    {:ok, view, _html} = live(conn, ~p"/companies")
    _html = render_async(view)

    view
    |> element("[phx-click='archive'][phx-value-id='#{company.id}']")
    |> render_click()

    assert Companies.get_company!(scope, company.id).archived_at

    {:ok, archived_view, _html} = live(conn, ~p"/companies?archived=archived")
    _html = render_async(archived_view)

    archived_view
    |> element("[phx-click='restore'][phx-value-id='#{company.id}']")
    |> render_click()

    refute Companies.get_company!(scope, company.id).archived_at
  end

  test "switches between table and card views", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/companies")
    _html = render_async(view)

    view
    |> element("#companies-view-cards")
    |> render_click()

    assert has_element?(view, "#companies-cards")

    view
    |> element("#companies-view-table")
    |> render_click()

    assert has_element?(view, "#companies-table")
  end

  defp org_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}
end
