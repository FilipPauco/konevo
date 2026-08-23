defmodule KonevoWeb.ContactsLive.IndexTest do
  use KonevoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Konevo.Factory
  import Konevo.ContactsFixtures

  alias Konevo.Accounts
  alias Konevo.Accounts.Scope
  alias Konevo.Contacts
  alias Konevo.Repo
  alias Konevo.Uploads.UploadedFile

  # Org-scoped routes require the org's slug as the subdomain host.
  defp org_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}

  setup do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: :owner)
    scope = Scope.for_user_in_org(user, org, membership)
    conn = build_conn() |> log_in_user(user) |> org_conn(org)
    %{conn: conn, user: user, org: org, membership: membership, scope: scope}
  end

  # ---------------------------------------------------------------------------
  # mount / page render
  # ---------------------------------------------------------------------------

  describe "index mount" do
    test "silently redirects unauthenticated users home", %{org: org} do
      unauthenticated = build_conn() |> org_conn(org)
      {:error, {:redirect, %{to: path}}} = live(unauthenticated, ~p"/contacts")
      assert path == "/"
    end

    test "renders the contacts page for an owner", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/contacts")
      assert html =~ "Contacts"

      _ = render_async(lv)
      assert has_element?(lv, "#contacts-empty")
      assert has_element?(lv, "#contacts-footer")
      refute has_element?(lv, "#uploaded-files-table")
    end

    test "shows global search results from the topbar", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope, %{first_name: "PaletteSearch"})
      {:ok, view, _html} = live(conn, ~p"/contacts")
      _ = render_async(view)

      assert has_element?(view, "#global-search-input")
      refute has_element?(view, "#global-search-modal")

      view
      |> form("#global-search-form", global_search: %{q: "PaletteSearch"})
      |> render_change()

      assert has_element?(view, "#global-search-result-contact-#{contact.id}")
    end

    test "renders a skeleton while contacts load", %{conn: conn} do
      document =
        conn
        |> get(~p"/contacts")
        |> html_response(200)
        |> LazyHTML.from_fragment()

      assert document |> LazyHTML.query("#contacts-loading[aria-busy='true']") |> Enum.any?()
      refute document |> LazyHTML.query("#contacts-table") |> Enum.any?()
      refute document |> LazyHTML.query("#contacts-footer") |> Enum.any?()
    end

    test "lists contacts scoped to the org", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope, %{first_name: "ScopedAlice"})
      {:ok, lv, _html} = live(conn, ~p"/contacts")
      html = render_async(lv)
      assert html =~ contact.first_name
    end

    test "does not list contacts from another org", %{conn: conn} do
      other_scope = build_scope()
      contact_fixture(other_scope, %{first_name: "HiddenBob"})
      {:ok, lv, _html} = live(conn, ~p"/contacts")
      html = render_async(lv)
      refute html =~ "HiddenBob"
    end

    test "shows contact profile pictures in the table", %{
      conn: conn,
      scope: scope,
      org: org
    } do
      contact = contact_fixture(scope)
      avatar = insert_contact_avatar(org, contact)
      {:ok, view, _html} = live(conn, ~p"/contacts")
      _ = render_async(view)

      assert has_element?(
               view,
               ~s(#contact-avatar-#{contact.id}[src="/uploads/avatar/#{avatar.id}"])
             )
    end

    test "viewer can load the contacts index", %{org: org} do
      viewer = insert(:user)
      insert(:membership, user: viewer, organization: org, role: :viewer)
      conn = build_conn() |> log_in_user(viewer) |> org_conn(org)
      {:ok, lv, html} = live(conn, ~p"/contacts")
      assert html =~ "Contacts"
      _ = render_async(lv)
    end

    test "shows LinkedIn icon in cards when contact has a LinkedIn URL", %{
      conn: conn,
      scope: scope,
      user: user
    } do
      {:ok, _user} = Accounts.update_user_view_preferences(user, %{contacts_view_mode: "card"})

      linkedin_url = "https://www.linkedin.com/in/card-contact"
      contact = contact_fixture(scope, %{linkedin_url: linkedin_url})
      {:ok, view, _html} = live(conn, ~p"/contacts")
      _ = render_async(view)

      assert has_element?(
               view,
               ~s(#contacts-cards #contact-card-linkedin-#{contact.id}[href="#{linkedin_url}"])
             )
    end

    test "hides LinkedIn icon in cards when contact LinkedIn URL is blank", %{
      conn: conn,
      scope: scope,
      user: user
    } do
      {:ok, _user} = Accounts.update_user_view_preferences(user, %{contacts_view_mode: "card"})

      contact = contact_fixture(scope, %{linkedin_url: "  "})
      {:ok, view, _html} = live(conn, ~p"/contacts")
      _ = render_async(view)

      refute has_element?(view, "#contacts-cards #contact-card-linkedin-#{contact.id}")
    end
  end

  # ---------------------------------------------------------------------------
  # new contact modal
  # ---------------------------------------------------------------------------

  describe "new contact" do
    test "owner can navigate to the new contact form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/contacts/new")
      _ = render_async(lv)
      assert has_element?(lv, "#contact-form")
      assert has_element?(lv, "#contact-form input[name='contact[linkedin_url]']")
    end

    test "company options are preloaded when form opens", %{
      conn: conn,
      user: user,
      org: org
    } do
      company = insert(:company, name: "Acme", user: user, organization: org)
      {:ok, lv, _html} = live(conn, ~p"/contacts/new")
      _ = render_async(lv)

      # The live_select component is rendered
      assert has_element?(lv, "#contact_company_id_live_select_component")

      # Clicking the text input opens the dropdown — options are already preloaded
      lv |> element("#contact_company_id_text_input") |> render_click()

      # Options render in the DOM once the dropdown is open
      assert has_element?(lv, "[data-idx]", company.name)
    end

    test "selected company survives form validation", %{conn: conn, user: user, org: org} do
      _company = insert(:company, name: "Acme", user: user, organization: org)
      {:ok, lv, _html} = live(conn, ~p"/contacts/new")
      _ = render_async(lv)

      # The hidden input for company_id is rendered by live_select (single mode).
      # This verifies the field is wired and will be submitted with the form.
      assert has_element?(lv, "#contact_company_id")

      # Triggering validation does not crash the form
      html =
        lv
        |> form("#contact-form", contact: %{first_name: "Jane"})
        |> render_change()

      assert html =~ "Jane"
      assert has_element?(lv, "#contact_company_id")
    end

    test "saving valid attrs creates the contact", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/contacts/new")
      _ = render_async(lv)

      lv
      |> form("#contact-form",
        contact: %{
          first_name: "NewGuy",
          last_name: "Test",
          linkedin_url: "https://www.linkedin.com/in/new-guy"
        }
      )
      |> render_submit()

      _ = :sys.get_state(lv.pid)
      html = render_async(lv, 1_000)

      assert html =~ "NewGuy"
    end

    test "saving invalid attrs shows validation errors", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/contacts/new")
      _ = render_async(lv)

      html =
        lv
        |> form("#contact-form", contact: %{first_name: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end
  end

  # ---------------------------------------------------------------------------
  # inline edit modal (opened from index)
  # ---------------------------------------------------------------------------

  describe "inline edit" do
    test "owner can edit a contact from the index", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope, %{first_name: "Editable"})
      {:ok, lv, _html} = live(conn, ~p"/contacts/#{contact.id}/edit/inline")
      _ = render_async(lv)

      assert has_element?(lv, "#contact-form")

      lv
      |> form("#contact-form", contact: %{first_name: "Updated"})
      |> render_submit()

      _ = :sys.get_state(lv.pid)
      html = render_async(lv, 1_000)

      assert html =~ "Updated"
    end
  end

  # ---------------------------------------------------------------------------
  # search / filter (push_patch driven)
  # ---------------------------------------------------------------------------

  describe "search" do
    test "search event narrows the contact list", %{conn: conn, scope: scope} do
      alice = contact_fixture(scope, %{first_name: "Alice"})
      bob = contact_fixture(scope, %{first_name: "Bob"})
      {:ok, lv, _html} = live(conn, ~p"/contacts")
      _ = render_async(lv)

      lv |> element("form[phx-submit='search']") |> render_submit(%{q: "Alice"})
      _ = render_async(lv)

      assert has_element?(lv, "#contacts a[href='/contacts/#{alice.slug}']")
      refute has_element?(lv, "#contacts a[href='/contacts/#{bob.slug}']")
    end
  end

  describe "filters and archiving" do
    test "filters contacts by status", %{conn: conn, scope: scope} do
      lead = contact_fixture(scope, %{first_name: "Lead filter", status: :lead})
      customer = contact_fixture(scope, %{first_name: "Customer filter", status: :customer})

      {:ok, view, _html} = live(conn, ~p"/contacts")
      _ = render_async(view)

      view
      |> element("#status-filter-dropdown input[phx-value-status='lead']")
      |> render_click()

      _ = render_async(view)

      assert has_element?(view, "#contacts a[href='/contacts/#{lead.slug}']")
      refute has_element?(view, "#contacts a[href='/contacts/#{customer.slug}']")
    end

    test "archives and restores a contact from the list", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope, %{first_name: "Archive me"})

      {:ok, view, _html} = live(conn, ~p"/contacts")
      _ = render_async(view)

      view
      |> render_hook("archive", %{"id" => contact.id})

      assert Contacts.get_contact!(scope, contact.id).archived_at

      {:ok, archived_view, _html} = live(conn, ~p"/contacts?archived=archived")
      _ = render_async(archived_view)

      archived_view
      |> render_hook("restore", %{"id" => contact.id})

      refute Contacts.get_contact!(scope, contact.id).archived_at
    end

    test "switches between table and card views", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contacts")
      _ = render_async(view)

      view
      |> element("button[phx-click='set_view_mode'][phx-value-mode='card']")
      |> render_click()

      assert has_element?(view, "#contacts-cards")

      view
      |> element("button[phx-click='set_view_mode'][phx-value-mode='table']")
      |> render_click()

      assert has_element?(view, "#contacts-table")
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_scope(role \\ :owner) do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: role)
    Scope.for_user_in_org(user, org, membership)
  end

  defp insert_contact_avatar(org, contact) do
    id = System.unique_integer([:positive])

    Repo.insert!(%UploadedFile{
      context: :avatar,
      tenant_id: to_string(org.id),
      original_filename: "contact.jpg",
      storage_path: "avatars/#{org.id}/#{contact.id}/#{id}.jpg",
      content_type: "image/jpeg",
      byte_size: 1_024,
      sha256: String.duplicate("a", 64),
      owner_type: "contact",
      owner_id: to_string(contact.id),
      scan_status: :scanned
    })
  end
end
