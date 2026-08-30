defmodule KonevoWeb.ContactsLive.ShowTest do
  use KonevoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Konevo.Factory
  import Konevo.ContactsFixtures
  import Konevo.DealsFixtures
  import Konevo.TasksFixtures

  alias Konevo.Accounts.Scope
  alias Konevo.Contacts
  alias Konevo.Repo
  alias Konevo.Tasks
  alias Konevo.Uploads.UploadedFile

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
  # mount / render
  # ---------------------------------------------------------------------------

  describe "show mount" do
    test "silently redirects unauthenticated users home", %{scope: scope, org: org} do
      contact = contact_fixture(scope)
      unauthenticated = build_conn() |> org_conn(org)
      {:error, {:redirect, %{to: path}}} = live(unauthenticated, ~p"/contacts/#{contact.id}")
      assert path == "/"
    end

    test "renders the contact's name", %{conn: conn, scope: scope} do
      contact =
        contact_fixture(scope, %{
          first_name: "Jane",
          last_name: "Doe",
          linkedin_url: "https://www.linkedin.com/in/jane-doe"
        })

      {:ok, _lv, html} = live(conn, ~p"/contacts/#{contact.id}")
      assert html =~ "Jane"
      assert html =~ "Doe"
      assert html =~ "https://www.linkedin.com/in/jane-doe"
    end

    test "returns to the filtered contacts list", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope, %{first_name: "Jane", last_name: "Doe"})

      {:ok, view, _html} =
        live(conn, ~p"/contacts/#{contact}?#{[return_to: "/contacts?search=jane"]}")

      assert has_element?(view, "#contact-back-link a[href='/contacts?search=jane']")
    end

    test "uses the contacts list for an invalid return path", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact}?return_to=https://example.com")

      assert has_element?(view, "#contact-back-link a[href='/contacts']")
    end

    test "renders linked task timeline", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope)
      task = task_fixture(scope, %{title: "Call this contact", contact: contact})

      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      assert has_element?(view, "#contact-task-timeline")
      assert has_element?(view, "#contact-task-timeline-task-#{task.id}")
    end

    test "renders deals linked to the contact", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope)
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

      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      assert has_element?(view, "#contact-deals")
      assert has_element?(view, "#contact-deal-#{deal.id}")
    end

    test "creates a task from contact detail without navigating to tasks", %{
      conn: conn,
      scope: scope
    } do
      contact = contact_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      view |> element("#contact-add-task") |> render_click()

      assert has_element?(view, "#contact-task-modal #task-form")

      view
      |> form("#task-form",
        task: %{
          title: "Local contact task",
          due_date: "2026-07-20T09:00",
          contact_id: contact.id
        }
      )
      |> render_submit()

      assert {:ok, tasks} = Tasks.list_tasks_for_contact(scope, contact)
      task = Enum.find(tasks, &(&1.title == "Local contact task"))

      assert task
      assert has_element?(view, "#contact-task-timeline-task-#{task.id}")
      refute has_element?(view, "#contact-task-modal")
    end

    test "keeps the preselected contact label when validating a new task", %{
      conn: conn,
      scope: scope
    } do
      contact =
        contact_fixture(scope, %{
          first_name: "Jane",
          last_name: "Doe",
          email: "jane@example.com"
        })

      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")
      view |> element("#contact-add-task") |> render_click()

      view
      |> form("#task-form", task: %{title: "Follow up", contact_id: contact.id})
      |> render_change()

      assert has_element?(
               view,
               "#task_contact_id_live_select_component input[type='text'][value='Jane Doe (jane@example.com)']"
             )
    end

    test "raises for a contact belonging to another org", %{conn: conn} do
      other_scope = build_scope()
      other_contact = contact_fixture(other_scope)

      assert {%{status: 404}, _call} = catch_exit(live(conn, ~p"/contacts/#{other_contact.id}"))
    end

    test "renders the contact profile-picture uploader", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      assert has_element?(view, "#contact-avatar-form")

      assert has_element?(
               view,
               ~s(#contact-avatar-form input[type="file"][accept=".jpg,.jpeg,.png,.gif,.webp"])
             )

      assert has_element?(view, "#contact-avatar-form input[data-phx-auto-upload]")
    end

    test "renders the latest tenant-scoped contact avatar", %{
      conn: conn,
      scope: scope,
      org: org
    } do
      contact = contact_fixture(scope)
      avatar = insert_contact_avatar(org, contact)

      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      assert has_element?(
               view,
               ~s(#contact-avatar-image[src="/uploads/avatar/#{avatar.id}"])
             )
    end

    test "viewer sees a static avatar without upload controls", %{org: org, scope: scope} do
      contact = contact_fixture(scope)
      viewer = insert(:user)
      insert(:membership, user: viewer, organization: org, role: :viewer)
      conn = build_conn() |> log_in_user(viewer) |> org_conn(org)

      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      assert has_element?(view, "#contact-avatar-static")
      refute has_element?(view, "#contact-avatar-form")
    end

    test "uploads a validated avatar when ImageMagick is unavailable", %{
      conn: conn,
      scope: scope
    } do
      contact = contact_fixture(scope)

      uploads_root =
        Path.join(System.tmp_dir!(), "contact-avatar-#{System.unique_integer([:positive])}")

      previous_root = Application.get_env(:konevo, :uploads_root)
      previous_mogrify = Application.get_env(:mogrify, :mogrify_command)

      Application.put_env(:konevo, :uploads_root, uploads_root)
      Application.put_env(:mogrify, :mogrify_command, path: "missing-image-magick")

      on_exit(fn ->
        restore_env(:konevo, :uploads_root, previous_root)
        restore_env(:mogrify, :mogrify_command, previous_mogrify)
        File.rm_rf!(uploads_root)
      end)

      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact.id}")

      upload =
        file_input(view, "#contact-avatar-form", :avatar, [
          %{
            name: "avatar.png",
            content: tiny_png(),
            type: "image/png"
          }
        ])

      _ = render_upload(upload, "avatar.png")

      assert has_element?(view, "#contact-avatar-image[src^='/uploads/avatar/']")
      assert has_element?(view, "#flash-success")
    end
  end

  # ---------------------------------------------------------------------------
  # delete
  # ---------------------------------------------------------------------------

  describe "delete" do
    test "owner can delete a contact and is redirected to /contacts", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope, %{first_name: "ToDelete"})
      {:ok, lv, _html} = live(conn, ~p"/contacts/#{contact.id}")

      lv |> element("button[phx-click='delete']") |> render_click()

      assert_redirect(lv, ~p"/contacts")
      assert_raise Ecto.NoResultsError, fn -> Contacts.get_contact!(scope, contact.id) end
    end

    # Authorization is enforced at the context layer (Contacts.delete_contact/2).
    # The delete button is rendered for all authenticated users; members are blocked
    # by Bodyguard when the event reaches the context — see contacts_test.exs.
  end

  describe "archiving" do
    test "owner can archive and restore a contact from the detail page", %{
      conn: conn,
      scope: scope
    } do
      contact = contact_fixture(scope, %{first_name: "Archive detail"})
      {:ok, view, _html} = live(conn, ~p"/contacts/#{contact}")

      view |> render_hook("archive", %{})
      assert Contacts.get_contact!(scope, contact.id).archived_at

      view |> render_hook("restore", %{})
      refute Contacts.get_contact!(scope, contact.id).archived_at
    end
  end

  # ---------------------------------------------------------------------------
  # notes editor
  # ---------------------------------------------------------------------------

  describe "notes" do
    test "owner can open the notes editor", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/contacts/#{contact.id}")

      # Two edit_notes buttons exist (Edit / Add a note). Click the first.
      html = lv |> element("button[aria-label='Edit notes']") |> render_click()

      assert html =~ "notes"
    end

    test "owner can save notes", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/contacts/#{contact.id}")

      lv |> element("button[aria-label='Edit notes']") |> render_click()

      # notes is a hidden input managed by a JS rich-text editor;
      # submit the form with its current (empty) value and assert the flash.
      html =
        lv
        |> form("[phx-submit='save_notes']")
        |> render_submit()

      assert html =~ "Notes saved"
    end

    test "owner can cancel notes editing", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/contacts/#{contact.id}")

      lv |> element("button[aria-label='Edit notes']") |> render_click()

      lv |> element("button[phx-click='cancel_notes']") |> render_click()

      refute has_element?(lv, "[phx-submit='save_notes']")
    end
  end

  # ---------------------------------------------------------------------------
  # edit form (from show page)
  # ---------------------------------------------------------------------------

  describe "edit contact from show" do
    test "owner can update a contact from show page", %{conn: conn, scope: scope} do
      contact = contact_fixture(scope, %{first_name: "Original"})
      {:ok, lv, _html} = live(conn, ~p"/contacts/#{contact.id}/edit")

      assert has_element?(lv, "#contact-form")
      assert has_element?(lv, "#contact-form input[name='contact[linkedin_url]']")

      lv
      |> form("#contact-form", contact: %{first_name: "Renamed"})
      |> render_submit()

      assert render(lv) =~ "Renamed"
    end

    test "renaming a contact from show page patches to the new slug", %{
      conn: conn,
      scope: scope
    } do
      contact = contact_fixture(scope, %{first_name: "Old", last_name: "Name"})
      {:ok, lv, _html} = live(conn, ~p"/contacts/#{contact.slug}/edit")

      lv
      |> form("#contact-form", contact: %{first_name: "New"})
      |> render_submit()

      updated = Contacts.get_contact!(scope, contact.id)

      assert updated.slug == "new-name"
      assert_patch(lv, ~p"/contacts/#{updated}")
      assert render(lv) =~ "New"
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

  defp tiny_png do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
