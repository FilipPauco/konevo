defmodule KonevoWeb.InboxLive.ShowTest do
  use KonevoWeb.ConnCase, async: false

  import Konevo.Factory
  import Phoenix.LiveViewTest

  alias Konevo.Accounts.Scope
  alias Konevo.Companies.Company
  alias Konevo.Inbox
  alias Konevo.Inbox.ScheduledEmail
  alias Konevo.Repo
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

  test "renders inline Gmail CID images from imported attachments", %{conn: conn, org: org} do
    thread = insert(:email_thread, organization: org, subject: "Inline image")

    email =
      insert(:email,
        organization: org,
        thread: thread,
        html_body: "<p>Here is the image:</p><img src=\"cid:ii_msrsgk970\">",
        inline_image_cids: %{"<ii_msrsgk970>" => "photo.png"},
        has_attachments: true
      )

    file =
      %UploadedFile{}
      |> UploadedFile.changeset(%{
        context: :mixed_attachment,
        tenant_id: to_string(org.id),
        original_filename: "photo.png",
        storage_path: "documents/inline-image-#{email.id}.png",
        content_type: "image/png",
        byte_size: 1,
        sha256: String.duplicate("a", 64),
        owner_type: "email",
        owner_id: to_string(email.id),
        scan_status: :scanned
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/inbox/#{thread.id}")

    assert render(view) =~ "/uploads/mixed_attachment/#{file.id}"
  end

  test "creates and links a contact from the latest inbound sender", %{
    conn: conn,
    org: org,
    scope: scope
  } do
    thread = insert(:email_thread, organization: org, subject: "Important lead")

    insert(:email,
      organization: org,
      thread: thread,
      from: "Jane Sender <jane.sender@acme.com>",
      received_at: ~U[2026-01-01 12:00:00Z],
      is_inbound: true
    )

    {:ok, view, _html} = live(conn, ~p"/inbox/#{thread.id}/contact/new")

    assert has_element?(view, "#contact-form")
    assert has_element?(view, "#contact_email[value='jane.sender@acme.com']")
    assert has_element?(view, "#contact_first_name[value='Jane']")
    assert has_element?(view, "#contact_last_name[value='Sender']")

    view
    |> form("#contact-form",
      contact: %{
        first_name: "Jane",
        last_name: "Sender",
        email: "jane.sender@acme.com",
        status: "lead"
      }
    )
    |> render_submit()

    assert_patch(view, ~p"/inbox/#{thread.id}")

    thread = Inbox.get_thread!(scope, thread.id)
    assert thread.contact.email == "jane.sender@acme.com"
  end

  test "prefills and creates a company from the sender domain", %{conn: conn, org: org} do
    thread = insert(:email_thread, organization: org, subject: "New account")

    insert(:email,
      organization: org,
      thread: thread,
      from: "Jane Sender <jane.sender@acme.com>",
      received_at: ~U[2026-01-01 12:00:00Z],
      is_inbound: true
    )

    {:ok, view, _html} = live(conn, ~p"/inbox/#{thread.id}/company/new")

    assert has_element?(view, "#company-form")
    assert has_element?(view, "#company_name[value='Acme']")
    assert has_element?(view, "#company_website[value='https://acme.com']")

    view
    |> form("#company-form",
      company: %{
        name: "Acme",
        website: "https://acme.com"
      }
    )
    |> render_submit()

    assert_patch(view, ~p"/inbox/#{thread.id}")
    assert Repo.get_by(Company, organization_id: org.id, name: "Acme")
  end

  test "shows reply schedule controls", %{conn: conn, org: org} do
    thread = insert(:email_thread, organization: org, subject: "Follow up")

    insert(:email,
      organization: org,
      thread: thread,
      from: "buyer@example.com",
      received_at: ~U[2026-01-01 12:00:00Z],
      is_inbound: true
    )

    {:ok, view, _html} = live(conn, ~p"/inbox/#{thread.id}")

    view
    |> element("#thread-header-reply")
    |> render_click()

    assert has_element?(view, "#reply-form")
    assert has_element?(view, "#reply-schedule-menu")
    assert has_element?(view, "#reply_scheduled_at")
  end

  test "opens guided AI drafting with an instruction and tone", %{conn: conn, org: org} do
    thread = insert(:email_thread, organization: org, subject: "Guided draft")

    insert(:email,
      organization: org,
      thread: thread,
      from: "buyer@example.com",
      received_at: ~U[2026-01-01 12:00:00Z],
      is_inbound: true
    )

    {:ok, view, _html} = live(conn, ~p"/inbox/#{thread.id}")

    view
    |> element("#thread-header-reply")
    |> render_click()

    view
    |> element("#generate-reply-draft")
    |> render_click()

    assert has_element?(view, "#ai-reply-guidance-form")
    assert has_element?(view, "#ai_reply_instruction")
    assert has_element?(view, "#ai_reply_tone")
    assert has_element?(view, "#generate-guided-reply-draft")
  end

  test "shows reply target before composer is opened", %{conn: conn, org: org} do
    thread = insert(:email_thread, organization: org, subject: "Follow up")

    insert(:email,
      organization: org,
      thread: thread,
      from: "older@example.com",
      received_at: ~U[2026-01-01 12:00:00Z],
      is_inbound: true
    )

    insert(:email,
      organization: org,
      thread: thread,
      from: "buyer@example.com",
      received_at: ~U[2026-01-02 12:00:00Z],
      is_inbound: true
    )

    {:ok, view, _html} = live(conn, ~p"/inbox/#{thread.id}")

    assert has_element?(view, "#thread-bottom-reply")
    assert render(view) =~ "Replying to"
    assert render(view) =~ "buyer@example.com"
  end

  test "schedules a reply from thread detail", %{conn: conn, org: org, user: user} do
    insert(:email_integration, organization: org, user: user, sync_enabled: true)
    thread = insert(:email_thread, organization: org, subject: "Follow up")

    insert(:email,
      organization: org,
      thread: thread,
      from: "buyer@example.com",
      received_at: ~U[2026-01-01 12:00:00Z],
      is_inbound: true
    )

    {:ok, view, _html} = live(conn, ~p"/inbox/#{thread.id}")

    view
    |> element("#thread-header-reply")
    |> render_click()

    render_submit(view, "send_reply", %{
      "reply" => %{"body" => "Following up", "schedule_preset" => "tomorrow"}
    })

    assert render(view) =~ "Reply scheduled"

    assert %ScheduledEmail{kind: :reply, status: :pending, to: ["buyer@example.com"]} =
             Repo.get_by(ScheduledEmail, organization_id: org.id, email_thread_id: thread.id)
  end

  test "opens a manual task form without running task extraction", %{conn: conn, org: org} do
    thread = insert(:email_thread, organization: org, subject: "Manual task")

    {:ok, view, _html} = live(conn, "/inbox/#{thread.id}/task/new?mode=manual")

    assert has_element?(view, "#task-review-form")
    assert has_element?(view, "#create-selected-tasks")
    assert has_element?(view, "#create-task-from-thread")
    refute has_element?(view, "#add-manual-task-suggestion")
    refute has_element?(view, "#task-extraction-loading")
  end

  test "resolves, reopens, and favorites a thread", %{conn: conn, org: org, scope: scope} do
    thread = insert(:email_thread, organization: org, subject: "Thread state actions")
    {:ok, view, _html} = live(conn, ~p"/inbox/#{thread.id}")

    view |> render_hook("resolve", %{})
    refute Inbox.get_thread!(scope, thread.id).is_unresolved

    view |> render_hook("reopen", %{})
    assert Inbox.get_thread!(scope, thread.id).is_unresolved

    view |> render_hook("toggle_favorite", %{})
    assert Inbox.get_thread!(scope, thread.id).is_favorite
  end

  test "moves a thread to the bin and restores it", %{conn: conn, org: org, scope: scope} do
    thread = insert(:email_thread, organization: org, subject: "Bin and restore")
    {:ok, view, _html} = live(conn, ~p"/inbox/#{thread.id}")

    view |> render_hook("move_to_bin", %{})
    assert_redirect(view, ~p"/inbox?view=bin")
    assert Inbox.get_thread!(scope, thread.id).trashed_at

    {:ok, restored_view, _html} = live(conn, ~p"/inbox/#{thread.id}")
    restored_view |> render_hook("restore", %{})

    refute Inbox.get_thread!(scope, thread.id).trashed_at
  end

  test "archives and unarchives a thread", %{conn: conn, org: org, scope: scope} do
    thread = insert(:email_thread, organization: org, subject: "Archive and unarchive")
    {:ok, view, _html} = live(conn, ~p"/inbox/#{thread.id}")

    view |> render_hook("archive", %{})
    assert_redirect(view, ~p"/inbox")
    assert Inbox.get_thread!(scope, thread.id).is_archived

    {:ok, archived_view, _html} = live(conn, ~p"/inbox/#{thread.id}")
    archived_view |> render_hook("unarchive", %{})

    refute Inbox.get_thread!(scope, thread.id).is_archived
  end
end
