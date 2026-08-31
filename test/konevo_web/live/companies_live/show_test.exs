defmodule KonevoWeb.CompaniesLive.ShowTest do
  use KonevoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Konevo.Factory
  import Konevo.CompaniesFixtures
  import Konevo.ContactsFixtures
  import Konevo.DealsFixtures
  import Konevo.TasksFixtures

  alias Konevo.Accounts.Scope
  alias Konevo.Companies
  alias Konevo.Contacts
  alias Konevo.Tasks

  setup do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: :owner)
    scope = Scope.for_user_in_org(user, org, membership)
    conn = build_conn() |> log_in_user(user) |> then(&%{&1 | host: "#{org.slug}.localhost"})
    %{conn: conn, scope: scope}
  end

  test "renders company details and related contacts", %{conn: conn, scope: scope} do
    company =
      company_fixture(scope, %{
        name: "Acme",
        industry: "Software",
        website: "https://acme.test",
        linkedin_url: "https://www.linkedin.com/company/acme"
      })

    contact = contact_fixture(scope, %{first_name: "Jane", company: company})
    {:ok, view, _html} = live(conn, ~p"/companies/#{company}")

    assert has_element?(view, "#company-details")
    assert has_element?(view, "a[href='https://www.linkedin.com/company/acme']")
    assert has_element?(view, "#company-contacts a[href='/contacts/#{contact.slug}']")
  end

  test "returns to the filtered company list", %{conn: conn, scope: scope} do
    company = company_fixture(scope, %{name: "Acme"})

    {:ok, view, _html} =
      live(conn, ~p"/companies/#{company}?#{[return_to: "/companies?search=acme"]}")

    assert has_element?(view, "#company-back-link a[href='/companies?search=acme']")
  end

  test "uses the company list for an invalid return path", %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company}?return_to=https://example.com")

    assert has_element?(view, "#company-back-link a[href='/companies']")
  end

  test "renders linked task timeline", %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    task = task_fixture(scope, %{title: "Company follow up", company: company})

    {:ok, view, _html} = live(conn, ~p"/companies/#{company}")

    assert has_element?(view, "#company-task-timeline")
    assert has_element?(view, "#company-task-timeline-task-#{task.id}")
  end

  test "renders deals linked through company contacts", %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    contact = contact_fixture(scope, %{company: company})
    stage = deal_stage_fixture(scope, %{name: "Qualified"})

    deal =
      insert(:deal,
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user,
        title: "Annual renewal"
      )

    {:ok, view, _html} = live(conn, ~p"/companies/#{company}")

    assert has_element?(view, "#company-deals")
    assert has_element?(view, "#company-deal-#{deal.id}")
  end

  test "creates a contact from company detail without navigating to contacts", %{
    conn: conn,
    scope: scope
  } do
    company = company_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company}")

    view |> element("#company-add-contact") |> render_click()

    assert has_element?(view, "#company-contact-modal #contact-form")

    view
    |> form("#contact-form",
      contact: %{
        first_name: "Local",
        last_name: "Contact",
        company_id: company.id
      }
    )
    |> render_submit()

    {contacts, _total} = Contacts.list_contacts(scope, company_ids: [company.id])
    contact = Enum.find(contacts, &(&1.first_name == "Local"))

    assert contact
    assert has_element?(view, "#company-contacts a[href='/contacts/#{contact.slug}']")
    refute has_element?(view, "#company-contact-modal")
  end

  test "keeps the preselected company label when validating a new contact", %{
    conn: conn,
    scope: scope
  } do
    company = company_fixture(scope, %{name: "Acme"})
    {:ok, view, _html} = live(conn, ~p"/companies/#{company}")

    view |> element("#company-add-contact") |> render_click()

    view
    |> form("#contact-form", contact: %{first_name: "Jane", company_id: company.id})
    |> render_change()

    assert has_element?(
             view,
             "#contact_company_id_live_select_component input[type='text'][value='Acme']"
           )
  end

  test "creates a task from company detail without navigating to tasks", %{
    conn: conn,
    scope: scope
  } do
    company = company_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company}")

    view |> element("#company-add-task") |> render_click()

    assert has_element?(view, "#company-task-modal #task-form")

    view
    |> form("#task-form",
      task: %{
        title: "Local company task",
        due_date: "2026-07-20T09:00",
        company_id: company.id
      }
    )
    |> render_submit()

    assert {:ok, tasks} = Tasks.list_tasks_for_company(scope, company)
    task = Enum.find(tasks, &(&1.title == "Local company task"))

    assert task
    assert has_element?(view, "#company-task-timeline-task-#{task.id}")
    refute has_element?(view, "#company-task-modal")
  end

  test "removes activity and places deals after tasks", %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    {:ok, view, html} = live(conn, ~p"/companies/#{company}")

    refute html =~ "Activity"
    assert has_element?(view, "#company-task-timeline")

    task_position = html |> :binary.match("company-task-timeline") |> elem(0)
    deals_position = html |> :binary.match("company-deals-card") |> elem(0)

    assert task_position < deals_position
  end

  test "edits notes", %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company}")
    view |> element("#edit-company-notes") |> render_click()
    assert has_element?(view, "#company-notes-form")

    view
    |> element("#company-notes-form")
    |> render_submit(%{"company" => %{"notes" => "Important account"}})

    assert render(view) =~ "Important account"
  end

  test "renaming a company patches to the new slug", %{conn: conn, scope: scope} do
    company = company_fixture(scope, %{name: "Old Company"})
    {:ok, view, _html} = live(conn, ~p"/companies/#{company}/edit")

    view
    |> form("#company-form", company: %{name: "Renamed Company"})
    |> render_submit()

    updated = Companies.get_company!(scope, company.id)

    assert updated.slug == "renamed-company"
    assert_patch(view, ~p"/companies/#{updated}?#{[return_to: "/companies"]}")
    assert render(view) =~ "Renamed Company"
  end

  test "deletes and redirects", %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company}")
    view |> element("#delete-company") |> render_click()
    assert_redirect(view, ~p"/companies")
    assert_raise Ecto.NoResultsError, fn -> Companies.get_company!(scope, company.id) end
  end

  test "archives and restores from the detail page", %{conn: conn, scope: scope} do
    company = company_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/companies/#{company}")

    view |> render_hook("archive", %{})
    assert Companies.get_company!(scope, company.id).archived_at

    view |> render_hook("restore", %{})
    refute Companies.get_company!(scope, company.id).archived_at
  end
end
