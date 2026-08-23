defmodule Konevo.InboxTest do
  use Konevo.DataCase, async: true

  import Konevo.Factory
  import Konevo.InboxFixtures

  alias Konevo.Accounts.Scope
  alias Konevo.Inbox
  alias Konevo.Inbox.{Email, EmailBranding, EmailIntegration, EmailThread, ScheduledEmail}
  alias Konevo.Repo
  alias Konevo.Uploads.UploadedFile

  defp build_scope(role \\ :owner) do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: role)
    Scope.for_user_in_org(user, org, membership)
  end

  setup do
    %{scope: build_scope(:owner)}
  end

  # ---------------------------------------------------------------------------
  # EmailIntegration
  # ---------------------------------------------------------------------------

  describe "list_integrations/1" do
    test "returns integrations scoped to org", %{scope: scope} do
      i1 = integration_fixture(scope, %{email_address: "a@example.com"})
      i2 = integration_fixture(scope, %{email_address: "b@example.com"})

      other_scope = build_scope()
      _hidden = integration_fixture(other_scope)

      integrations = Inbox.list_integrations(scope)
      ids = Enum.map(integrations, & &1.id)

      assert i1.id in ids
      assert i2.id in ids
      assert length(integrations) == 2
    end

    test "does not return another org's integrations", %{scope: scope} do
      other_scope = build_scope()
      other = integration_fixture(other_scope)

      integrations = Inbox.list_integrations(scope)
      refute other.id in Enum.map(integrations, & &1.id)
    end
  end

  describe "create_integration/2" do
    test "creates integration with valid attrs", %{scope: scope} do
      assert {:ok, %EmailIntegration{email_address: "me@gmail.com"}} =
               Inbox.create_integration(scope, %{provider: :gmail, email_address: "me@gmail.com"})
    end

    test "associates with scope org and user", %{scope: scope} do
      {:ok, integration} =
        Inbox.create_integration(scope, %{provider: :gmail, email_address: "me@gmail.com"})

      assert integration.organization_id == scope.org.id
      assert integration.user_id == scope.user.id
    end

    test "returns error changeset when email_address missing", %{scope: scope} do
      assert {:error, %Ecto.Changeset{}} =
               Inbox.create_integration(scope, %{provider: :gmail})
    end

    test "returns error changeset for invalid email", %{scope: scope} do
      assert {:error, %Ecto.Changeset{}} =
               Inbox.create_integration(scope, %{provider: :gmail, email_address: "not-an-email"})
    end

    test "returns unauthorized for viewer" do
      scope = build_scope(:viewer)
      assert {:error, :unauthorized} = Inbox.create_integration(scope, %{})
    end
  end

  describe "store_tokens/3" do
    test "updates OAuth token fields", %{scope: scope} do
      integration = integration_fixture(scope)
      expires_at = DateTime.add(DateTime.utc_now(:second), 3600)

      assert {:ok, updated} =
               Inbox.store_tokens(scope, integration, %{
                 access_token: "tok_access",
                 refresh_token: "tok_refresh",
                 token_expires_at: expires_at
               })

      assert updated.access_token == "tok_access"
      assert updated.refresh_token == "tok_refresh"
    end

    test "returns unauthorized for viewer" do
      owner_scope = build_scope(:owner)
      integration = integration_fixture(owner_scope)

      viewer = insert(:user)
      m = insert(:membership, user: viewer, organization: owner_scope.org, role: :viewer)
      viewer_scope = Scope.for_user_in_org(viewer, owner_scope.org, m)

      assert {:error, :unauthorized} = Inbox.store_tokens(viewer_scope, integration, %{})
    end
  end

  describe "connect_gmail/3" do
    test "preserves an existing refresh token when Google omits one", %{scope: scope} do
      existing =
        integration_fixture(scope, %{
          provider: :gmail,
          email_address: "me@gmail.com",
          access_token: "old_access",
          refresh_token: "old_refresh",
          sync_enabled: false
        })

      expires_at = DateTime.add(DateTime.utc_now(:second), 3600)

      assert {:ok, updated} =
               Inbox.connect_gmail(scope, "me@gmail.com", %{
                 access_token: "new_access",
                 refresh_token: nil,
                 token_expires_at: expires_at
               })

      assert updated.id == existing.id
      assert updated.access_token == "new_access"
      assert updated.refresh_token == "old_refresh"
      assert updated.sync_enabled == true
    end

    test "replaces refresh token when Google returns a new one", %{scope: scope} do
      integration_fixture(scope, %{
        provider: :gmail,
        email_address: "me@gmail.com",
        refresh_token: "old_refresh"
      })

      assert {:ok, updated} =
               Inbox.connect_gmail(scope, "me@gmail.com", %{
                 access_token: "new_access",
                 refresh_token: "new_refresh",
                 token_expires_at: DateTime.add(DateTime.utc_now(:second), 3600)
               })

      assert updated.refresh_token == "new_refresh"
    end
  end

  describe "set_primary/2" do
    test "marks integration as primary and clears others", %{scope: scope} do
      i1 = integration_fixture(scope, %{email_address: "a@example.com", is_primary: true})
      i2 = integration_fixture(scope, %{email_address: "b@example.com", is_primary: false})

      assert {:ok, updated} = Inbox.set_primary(scope, i2)
      assert updated.is_primary == true

      i1_after = Inbox.get_integration!(scope, i1.id)
      assert i1_after.is_primary == false
    end
  end

  describe "toggle_sync/2" do
    test "toggles sync_enabled", %{scope: scope} do
      integration = integration_fixture(scope, %{sync_enabled: true})
      assert {:ok, updated} = Inbox.toggle_sync(scope, integration)
      assert updated.sync_enabled == false

      assert {:ok, toggled_back} = Inbox.toggle_sync(scope, updated)
      assert toggled_back.sync_enabled == true
    end
  end

  describe "update_integration_signature/3" do
    test "updates sender signature", %{scope: scope} do
      integration = integration_fixture(scope)

      assert {:ok, updated} =
               Inbox.update_integration_signature(scope, integration, %{
                 "signature_html" => "Best,\nFilip"
               })

      assert updated.signature_html == "<p>Best,<br />Filip</p>"
    end

    test "returns unauthorized for integrations outside the scope", %{scope: scope} do
      other_scope = build_scope()
      integration = integration_fixture(other_scope)

      assert {:error, :unauthorized} =
               Inbox.update_integration_signature(scope, integration, %{
                 "signature_html" => "Hidden"
               })
    end
  end

  describe "EmailBranding.apply/2" do
    test "appends html signature to plain text bodies", %{scope: scope} do
      integration =
        integration_fixture(scope, %{
          signature_html: "Best,<br>Filip"
        })

      body = EmailBranding.apply("Hello", integration)

      assert body =~ "<p>Hello</p>"
      assert body =~ ~s(<div class="konevo-email-signature">Best,<br>Filip</div>)
    end

    test "appends html signature to html bodies", %{scope: scope} do
      integration =
        integration_fixture(scope, %{
          signature_html: "<p>Best,<br>Filip</p>"
        })

      body = EmailBranding.apply("<p>Hello</p>", integration)

      assert body =~ ~s(<div class="konevo-email-signature"><p>Best,<br>Filip</p></div>)
      refute body =~ "konevo-email-footer"
      refute body =~ "konevo-email-image"
    end
  end

  describe "delete_integration/2" do
    test "deletes the integration", %{scope: scope} do
      integration = integration_fixture(scope)
      assert {:ok, _} = Inbox.delete_integration(scope, integration)

      assert_raise Ecto.NoResultsError, fn ->
        Inbox.get_integration!(scope, integration.id)
      end
    end

    test "returns unauthorized for member" do
      owner_scope = build_scope(:owner)
      integration = integration_fixture(owner_scope)

      member = insert(:user)
      m = insert(:membership, user: member, organization: owner_scope.org, role: :member)
      member_scope = Scope.for_user_in_org(member, owner_scope.org, m)

      assert {:error, :unauthorized} = Inbox.delete_integration(member_scope, integration)
    end

    test "allows a member to delete their own integration" do
      member_scope = build_scope(:member)
      integration = integration_fixture(member_scope)

      assert {:ok, _} = Inbox.delete_integration(member_scope, integration)
    end
  end

  # ---------------------------------------------------------------------------
  # EmailThread
  # ---------------------------------------------------------------------------

  describe "list_threads/2" do
    test "returns threads scoped to org", %{scope: scope} do
      t1 = thread_fixture(scope, %{subject: "Thread A"})
      t2 = thread_fixture(scope, %{subject: "Thread B"})

      other_scope = build_scope()
      _hidden = thread_fixture(other_scope)

      {threads, total} = Inbox.list_threads(scope)
      ids = Enum.map(threads, & &1.id)

      assert t1.id in ids
      assert t2.id in ids
      assert total == 2
    end

    test "loads email counts for thread rows", %{scope: scope} do
      thread = thread_fixture(scope)
      email_fixture(scope, thread)
      email_fixture(scope, thread)

      {threads, 1} = Inbox.list_threads(scope)

      assert hd(threads).email_count == 2
    end

    test "orders by latest thread activity by default", %{scope: scope} do
      now = DateTime.utc_now(:second)

      older =
        thread_fixture(scope, %{
          subject: "Older inbound",
          last_inbound_at: now,
          last_activity_at: DateTime.add(now, -3600)
        })

      latest =
        thread_fixture(scope, %{
          subject: "Latest reply",
          last_inbound_at: DateTime.add(now, -7200),
          last_activity_at: now
        })

      {threads, 2} = Inbox.list_threads(scope)

      assert Enum.map(threads, & &1.id) == [latest.id, older.id]
    end

    test "filters by category", %{scope: scope} do
      thread_fixture(scope, %{category: :lead})
      thread_fixture(scope, %{category: :support})

      {threads, total} = Inbox.list_threads(scope, category: :lead)
      assert total == 1
      assert hd(threads).category == :lead
    end

    test "filters unresolved threads", %{scope: scope} do
      thread_fixture(scope, %{is_unresolved: true})
      thread_fixture(scope, %{is_unresolved: false})

      {threads, total} = Inbox.list_threads(scope, unresolved: true)
      assert total == 1
      assert hd(threads).is_unresolved == true
    end

    test "excludes archived threads by default", %{scope: scope} do
      thread_fixture(scope, %{is_archived: false})
      _archived = thread_fixture(scope, %{is_archived: true})

      {_threads, total} = Inbox.list_threads(scope)
      assert total == 1
    end

    test "filters local CRM views", %{scope: scope} do
      favorite = thread_fixture(scope, %{is_favorite: true})
      sent = thread_fixture(scope, %{last_outbound_at: DateTime.utc_now(:second)})
      archived = thread_fixture(scope, %{is_archived: true})
      binned = thread_fixture(scope, %{trashed_at: DateTime.utc_now(:second)})

      {favorites, 1} = Inbox.list_threads(scope, view: :favorites)
      {sent_threads, 1} = Inbox.list_threads(scope, view: :sent)
      {archived_threads, 1} = Inbox.list_threads(scope, view: :archived)
      {bin_threads, 1} = Inbox.list_threads(scope, view: :bin)

      assert Enum.map(favorites, & &1.id) == [favorite.id]
      assert Enum.map(sent_threads, & &1.id) == [sent.id]
      assert Enum.map(archived_threads, & &1.id) == [archived.id]
      assert Enum.map(bin_threads, & &1.id) == [binned.id]
    end

    test "searches subject, snippet, and participants in the database", %{scope: scope} do
      subject = thread_fixture(scope, %{subject: "Renewal proposal"})
      snippet = thread_fixture(scope, %{subject: "Other", snippet: "mentions invoice"})
      participant = thread_fixture(scope, %{subject: "Other", participants: ["buyer@acme.test"]})
      _hidden = thread_fixture(scope, %{subject: "Nothing"})

      {subject_threads, 1} = Inbox.list_threads(scope, search: "renewal")
      {snippet_threads, 1} = Inbox.list_threads(scope, search: "invoice")
      {participant_threads, 1} = Inbox.list_threads(scope, search: "acme")

      assert hd(subject_threads).id == subject.id
      assert hd(snippet_threads).id == snippet.id
      assert hd(participant_threads).id == participant.id
    end

    test "paginates results", %{scope: scope} do
      Enum.each(1..5, fn _ -> thread_fixture(scope) end)

      {page1, total} = Inbox.list_threads(scope, page: 1, per_page: 2)
      {page2, _} = Inbox.list_threads(scope, page: 2, per_page: 2)

      assert total == 5
      assert length(page1) == 2
      assert length(page2) == 2
      refute Enum.any?(page1, fn t -> t.id in Enum.map(page2, & &1.id) end)
    end
  end

  describe "unresolved_queue/2" do
    test "returns only unresolved lead and customer threads", %{scope: scope} do
      lead = thread_fixture(scope, %{category: :lead, is_unresolved: true})
      customer = thread_fixture(scope, %{category: :customer, is_unresolved: true})
      _support = thread_fixture(scope, %{category: :support, is_unresolved: true})
      _resolved = thread_fixture(scope, %{category: :lead, is_unresolved: false})

      threads = Inbox.unresolved_queue(scope)
      ids = Enum.map(threads, & &1.id)

      assert lead.id in ids
      assert customer.id in ids
      assert length(threads) == 2
    end

    test "excludes archived threads", %{scope: scope} do
      _archived =
        thread_fixture(scope, %{category: :lead, is_unresolved: true, is_archived: true})

      threads = Inbox.unresolved_queue(scope)
      assert threads == []
    end
  end

  describe "get_thread!/2" do
    test "returns thread with emails preloaded", %{scope: scope} do
      thread = thread_fixture(scope)
      _email = email_fixture(scope, thread)

      result = Inbox.get_thread!(scope, thread.id)
      assert result.id == thread.id
      assert length(result.emails) == 1
    end

    test "raises when thread belongs to another org", %{scope: scope} do
      other_scope = build_scope()
      other_thread = thread_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn ->
        Inbox.get_thread!(scope, other_thread.id)
      end
    end
  end

  describe "create_thread/2" do
    test "creates thread with valid attrs", %{scope: scope} do
      assert {:ok, %EmailThread{subject: "Hello"}} =
               Inbox.create_thread(scope, %{subject: "Hello"})
    end

    test "associates with scope org", %{scope: scope} do
      {:ok, thread} = Inbox.create_thread(scope, %{subject: "Hello"})
      assert thread.organization_id == scope.org.id
    end

    test "returns error changeset when subject missing", %{scope: scope} do
      assert {:error, %Ecto.Changeset{}} = Inbox.create_thread(scope, %{})
    end
  end

  describe "resolve_thread/2" do
    test "marks thread as resolved", %{scope: scope} do
      thread = thread_fixture(scope, %{is_unresolved: true})
      assert {:ok, updated} = Inbox.resolve_thread(scope, thread)
      assert updated.is_unresolved == false
    end
  end

  describe "archive_thread/2" do
    test "archives and resolves thread", %{scope: scope} do
      thread = thread_fixture(scope, %{is_unresolved: true, is_archived: false})
      assert {:ok, updated} = Inbox.archive_thread(scope, thread)
      assert updated.is_archived == true
      assert updated.is_unresolved == false
    end
  end

  describe "local thread state actions" do
    test "toggles favorite", %{scope: scope} do
      thread = thread_fixture(scope, %{is_favorite: false})
      assert {:ok, updated} = Inbox.toggle_favorite(scope, thread)
      assert updated.is_favorite == true
    end

    test "marks read and unread", %{scope: scope} do
      thread = thread_fixture(scope, %{read_at: nil, thread_id_gmail: "gmail-thread-1"})
      assert {:ok, read} = Inbox.mark_read(scope, thread)
      assert %DateTime{} = read.read_at

      assert Enum.any?(Repo.all(Oban.Job), fn job ->
               job.worker == "Konevo.Workers.GmailThreadReadStateWorker" and
                 job.args == %{"thread_id" => thread.id, "read" => true}
             end)

      assert {:ok, unread} = Inbox.mark_unread(scope, read)
      assert unread.read_at == nil
    end

    test "moves to bin and restores", %{scope: scope} do
      thread = thread_fixture(scope, %{trashed_at: nil, is_archived: true})
      assert {:ok, trashed} = Inbox.move_to_bin(scope, thread)
      assert %DateTime{} = trashed.trashed_at
      assert trashed.is_archived == false

      assert {:ok, restored} = Inbox.restore_thread(scope, trashed)
      assert restored.trashed_at == nil
    end
  end

  describe "link_contact/3" do
    test "links a contact to a thread", %{scope: scope} do
      thread = thread_fixture(scope)
      contact = insert(:contact, organization: scope.org, user: scope.user)

      assert {:ok, updated} = Inbox.link_contact(scope, thread, contact.id)
      assert updated.contact_id == contact.id
    end
  end

  describe "link_deal/3" do
    test "links a deal to a thread", %{scope: scope} do
      thread = thread_fixture(scope)
      stage = insert(:deal_stage, organization: scope.org)
      contact = insert(:contact, organization: scope.org, user: scope.user)

      deal =
        insert(:deal,
          organization: scope.org,
          stage: stage,
          contact: contact,
          owner: scope.user,
          created_by: scope.user
        )

      assert {:ok, updated} = Inbox.link_deal(scope, thread, deal.id)
      assert updated.deal_id == deal.id
    end
  end

  # ---------------------------------------------------------------------------
  # Emails
  # ---------------------------------------------------------------------------

  describe "store_email/3" do
    test "stores an email in a thread", %{scope: scope} do
      thread = thread_fixture(scope)

      assert {:ok, %Email{}} =
               Inbox.store_email(scope, thread, %{
                 message_id: "unique-msg-001@mail.example.com",
                 from: "jane@acme.com",
                 to: ["us@company.com"],
                 received_at: DateTime.utc_now(:second),
                 is_inbound: true
               })
    end

    test "is idempotent — returns existing email on duplicate message_id", %{scope: scope} do
      thread = thread_fixture(scope)

      attrs = %{
        message_id: "dup-msg-001@mail.example.com",
        from: "jane@acme.com",
        to: ["us@company.com"],
        received_at: DateTime.utc_now(:second),
        is_inbound: true
      }

      {:ok, first} = Inbox.store_email(scope, thread, attrs)
      {:ok, second} = Inbox.store_email(scope, thread, attrs)

      assert first.id == second.id
    end

    test "new inbound reply moves a local archived thread back to the inbox", %{scope: scope} do
      thread =
        thread_fixture(scope, %{
          is_archived: true,
          is_unresolved: false,
          snippet: "Original message",
          participants: ["old@example.com"],
          read_at: DateTime.utc_now(:second),
          trashed_at: DateTime.utc_now(:second)
        })

      assert {:ok, %Email{}} =
               Inbox.store_email(scope, thread, %{
                 message_id: "reply-msg-001@mail.example.com",
                 from: "jane@acme.com",
                 to: ["us@company.com"],
                 body: "Latest reply body",
                 received_at: DateTime.utc_now(:second),
                 is_inbound: true
               })

      thread = Inbox.get_thread!(scope, thread.id)

      assert thread.is_archived == false
      assert thread.trashed_at == nil
      assert thread.is_unresolved == true
      assert thread.read_at == nil
      assert thread.snippet == "Latest reply body"
      assert thread.participants == ["jane@acme.com", "old@example.com"]
    end
  end

  describe "list_emails/1" do
    test "returns emails ordered by received_at", %{scope: scope} do
      thread = thread_fixture(scope)
      now = DateTime.utc_now(:second)

      e1 =
        insert(:email,
          thread: thread,
          organization: scope.org,
          received_at: DateTime.add(now, -100)
        )

      e2 = insert(:email, thread: thread, organization: scope.org, received_at: now)

      emails = Inbox.list_emails(thread)
      ids = Enum.map(emails, & &1.id)

      assert ids == [e1.id, e2.id]
    end
  end

  # ---------------------------------------------------------------------------
  # Stats
  # ---------------------------------------------------------------------------

  describe "count_threads_by_category/1" do
    test "returns counts grouped by category", %{scope: scope} do
      thread_fixture(scope, %{category: :lead})
      thread_fixture(scope, %{category: :lead})
      thread_fixture(scope, %{category: :support})

      counts = Inbox.count_threads_by_category(scope)
      assert counts[:lead] == 2
      assert counts[:support] == 1
    end

    test "excludes another org's threads", %{scope: scope} do
      other_scope = build_scope()
      thread_fixture(other_scope, %{category: :lead})

      counts = Inbox.count_threads_by_category(scope)
      assert Map.get(counts, :lead, 0) == 0
    end
  end

  describe "total_revenue_at_risk/1" do
    test "sums revenue_at_risk for unresolved lead and customer threads", %{scope: scope} do
      thread_fixture(scope, %{
        category: :lead,
        is_unresolved: true,
        revenue_at_risk: Decimal.new("1000.00")
      })

      thread_fixture(scope, %{
        category: :customer,
        is_unresolved: true,
        revenue_at_risk: Decimal.new("2500.00")
      })

      thread_fixture(scope, %{
        category: :support,
        is_unresolved: true,
        revenue_at_risk: Decimal.new("500.00")
      })

      total = Inbox.total_revenue_at_risk(scope)
      assert Decimal.equal?(total, Decimal.new("3500.00"))
    end

    test "returns 0 when no unresolved threads", %{scope: scope} do
      result = Inbox.total_revenue_at_risk(scope)
      assert Decimal.equal?(result, Decimal.new(0))
    end
  end

  # ---------------------------------------------------------------------------
  # Reply sending
  # ---------------------------------------------------------------------------

  describe "send_reply/3" do
    test "returns error when no Gmail integration exists for the org", %{scope: scope} do
      thread =
        thread_fixture(scope, %{
          thread_id_gmail: "gmail-thread-123",
          participants: ["other@example.com"]
        })

      assert {:error, :no_integration} = Inbox.send_reply(scope, thread, "Hello there!")
    end

    test "returns error when all integrations are sync_disabled", %{scope: scope} do
      _disabled =
        integration_fixture(scope, %{
          sync_enabled: false,
          email_address: "me@gmail.com"
        })

      thread =
        thread_fixture(scope, %{
          thread_id_gmail: "gmail-thread-456",
          participants: ["other@example.com"]
        })

      assert {:error, :no_integration} = Inbox.send_reply(scope, thread, "Hello!")
    end

    test "returns unauthorized for viewer" do
      owner_scope = build_scope(:owner)
      thread = thread_fixture(owner_scope, %{thread_id_gmail: "gmail-thread-789"})

      viewer = insert(:user)
      m = insert(:membership, user: viewer, organization: owner_scope.org, role: :viewer)
      viewer_scope = Scope.for_user_in_org(viewer, owner_scope.org, m)

      assert {:error, :unauthorized} = Inbox.send_reply(viewer_scope, thread, "Hello!")
    end
  end

  # ---------------------------------------------------------------------------
  # Scheduled Emails
  # ---------------------------------------------------------------------------

  describe "send_message/2" do
    test "rejects invalid to, cc, and bcc addresses before delivery", %{scope: scope} do
      attrs = %{"to" => "buyer@example.com", "body" => "Hello"}

      assert {:error, {:invalid_recipients, %{to: ["not-an-email"]}}} =
               Inbox.send_message(scope, Map.put(attrs, "to", "not-an-email"))

      assert {:error, {:invalid_recipients, %{cc: ["not-an-email"]}}} =
               Inbox.send_message(scope, Map.put(attrs, "cc", "not-an-email"))

      assert {:error, {:invalid_recipients, %{bcc: ["not-an-email"]}}} =
               Inbox.send_message(scope, Map.put(attrs, "bcc", "not-an-email"))
    end
  end

  describe "schedule_message/2" do
    test "schedules a new email with valid attrs", %{scope: scope} do
      integration_fixture(scope)
      scheduled_at = DateTime.add(DateTime.utc_now(:second), 3600)

      assert {:ok, %ScheduledEmail{} = scheduled_email} =
               Inbox.schedule_message(scope, %{
                 "to" => "buyer@example.com",
                 "subject" => "Proposal",
                 "body" => "Here is the proposal",
                 "scheduled_at" => scheduled_at
               })

      assert scheduled_email.organization_id == scope.org.id
      assert scheduled_email.scheduled_by_id == scope.user.id
      assert scheduled_email.kind == :new_message
      assert scheduled_email.status == :pending
      assert scheduled_email.to == ["buyer@example.com"]
    end

    test "schedules a new email with datetime-local minute precision", %{scope: scope} do
      integration_fixture(scope)

      local_scheduled_at =
        Konevo.DateTime.local_today()
        |> Date.add(1)
        |> NaiveDateTime.new!(~T[09:30:00])

      scheduled_at_value = Calendar.strftime(local_scheduled_at, "%Y-%m-%dT%H:%M")

      assert {:ok, %ScheduledEmail{} = scheduled_email} =
               Inbox.schedule_message(scope, %{
                 "to" => "buyer@example.com",
                 "subject" => "Proposal",
                 "body" => "Here is the proposal",
                 "scheduled_at" => scheduled_at_value
               })

      assert scheduled_email.scheduled_at ==
               Konevo.DateTime.from_local_naive!(local_scheduled_at)
    end

    test "schedules a new email with draft attachments", %{scope: scope} do
      integration_fixture(scope)
      scheduled_at = DateTime.add(DateTime.utc_now(:second), 3600)
      attachment_owner_id = Ecto.UUID.generate()
      file = insert_draft_attachment(scope, attachment_owner_id)

      assert {:ok, %ScheduledEmail{} = scheduled_email} =
               Inbox.schedule_message(scope, %{
                 "to" => "buyer@example.com",
                 "subject" => "Proposal",
                 "body" => "Here is the proposal",
                 "scheduled_at" => scheduled_at,
                 "attachment_owner_id" => attachment_owner_id,
                 "attachment_ids" => [to_string(file.id)]
               })

      assert scheduled_email.attachment_owner_id == attachment_owner_id
      assert scheduled_email.attachment_ids == [file.id]
    end

    test "requires active Gmail integration", %{scope: scope} do
      assert {:error, :no_integration} =
               Inbox.schedule_message(scope, %{
                 "to" => "buyer@example.com",
                 "body" => "Hello",
                 "scheduled_at" => DateTime.add(DateTime.utc_now(:second), 3600)
               })
    end

    test "rejects missing recipient, missing body, and too-soon schedule time", %{scope: scope} do
      integration_fixture(scope)
      future = DateTime.add(DateTime.utc_now(:second), 3600)
      this_minute = DateTime.utc_now(:second) |> Map.replace!(:second, 0)

      assert {:error, :missing_recipient} =
               Inbox.schedule_message(scope, %{"body" => "Hi", "scheduled_at" => future})

      assert {:error, :missing_body} =
               Inbox.schedule_message(scope, %{
                 "to" => "buyer@example.com",
                 "scheduled_at" => future
               })

      assert {:error, :scheduled_at_too_soon} =
               Inbox.schedule_message(scope, %{
                 "to" => "buyer@example.com",
                 "body" => "Hi",
                 "scheduled_at" => DateTime.add(DateTime.utc_now(:second), -60)
               })

      assert {:error, :scheduled_at_too_soon} =
               Inbox.schedule_message(scope, %{
                 "to" => "buyer@example.com",
                 "body" => "Hi",
                 "scheduled_at" => this_minute
               })
    end
  end

  describe "schedule_reply/4" do
    test "schedules a reply with thread metadata", %{scope: scope} do
      integration_fixture(scope)

      thread =
        thread_fixture(scope, %{
          subject: "Question",
          thread_id_gmail: "gmail-thread-123",
          participants: ["buyer@example.com"]
        })

      scheduled_at = DateTime.add(DateTime.utc_now(:second), 3600)

      assert {:ok, %ScheduledEmail{} = scheduled_email} =
               Inbox.schedule_reply(scope, thread, "Thanks for reaching out", scheduled_at)

      assert scheduled_email.kind == :reply
      assert scheduled_email.email_thread_id == thread.id
      assert scheduled_email.gmail_thread_id == "gmail-thread-123"
      assert scheduled_email.subject == "Re: Question"
      assert scheduled_email.to == ["buyer@example.com"]
    end

    test "schedules a reply with draft attachments", %{scope: scope} do
      integration_fixture(scope)

      thread =
        thread_fixture(scope, %{
          subject: "Question",
          thread_id_gmail: "gmail-thread-123",
          participants: ["buyer@example.com"]
        })

      scheduled_at = DateTime.add(DateTime.utc_now(:second), 3600)
      attachment_owner_id = Ecto.UUID.generate()
      file = insert_draft_attachment(scope, attachment_owner_id)

      assert {:ok, %ScheduledEmail{} = scheduled_email} =
               Inbox.schedule_reply(scope, thread, "Thanks", scheduled_at,
                 attachment_owner_id: attachment_owner_id,
                 attachment_ids: [file.id]
               )

      assert scheduled_email.attachment_owner_id == attachment_owner_id
      assert scheduled_email.attachment_ids == [file.id]
    end

    test "returns unauthorized when thread belongs to another org", %{scope: scope} do
      integration_fixture(scope)
      other_scope = build_scope()
      thread = thread_fixture(other_scope, %{participants: ["buyer@example.com"]})

      assert {:error, :unauthorized} =
               Inbox.schedule_reply(
                 scope,
                 thread,
                 "Hi",
                 DateTime.add(DateTime.utc_now(:second), 3600)
               )
    end
  end

  describe "list_scheduled_emails/2 and cancel_scheduled_email/2" do
    test "lists scheduled emails scoped to org", %{scope: scope} do
      scheduled = insert(:scheduled_email, organization: scope.org, scheduled_by: scope.user)
      other_scope = build_scope()

      _hidden =
        insert(:scheduled_email, organization: other_scope.org, scheduled_by: other_scope.user)

      {scheduled_emails, total} = Inbox.list_scheduled_emails(scope)

      assert total == 1
      assert Enum.map(scheduled_emails, & &1.id) == [scheduled.id]
    end

    test "lists scheduled emails newest created first", %{scope: scope} do
      now = DateTime.utc_now(:second)

      older =
        insert(:scheduled_email,
          organization: scope.org,
          scheduled_by: scope.user,
          inserted_at: DateTime.add(now, -120, :second)
        )

      newer =
        insert(:scheduled_email,
          organization: scope.org,
          scheduled_by: scope.user,
          inserted_at: DateTime.add(now, -60, :second)
        )

      {scheduled_emails, total} = Inbox.list_scheduled_emails(scope)

      assert total == 2
      assert Enum.map(scheduled_emails, & &1.id) == [newer.id, older.id]
    end

    test "searches scheduled emails by text", %{scope: scope} do
      subject =
        insert(:scheduled_email,
          organization: scope.org,
          scheduled_by: scope.user,
          subject: "Renewal follow-up",
          body: "Checking in"
        )

      body =
        insert(:scheduled_email,
          organization: scope.org,
          scheduled_by: scope.user,
          subject: "Next steps",
          body: "Please review the invoice"
        )

      recipient =
        insert(:scheduled_email,
          organization: scope.org,
          scheduled_by: scope.user,
          subject: "Hello",
          body: "Quick note",
          to: ["buyer@acme.test"],
          cc: ["copy@acme.test"]
        )

      _hidden =
        insert(:scheduled_email,
          organization: scope.org,
          scheduled_by: scope.user,
          subject: "Unrelated",
          body: "Nothing to see"
        )

      assert {[found], 1} = Inbox.list_scheduled_emails(scope, search: "renewal")
      assert found.id == subject.id

      assert {[found], 1} = Inbox.list_scheduled_emails(scope, search: "invoice")
      assert found.id == body.id

      assert {[found], 1} = Inbox.list_scheduled_emails(scope, search: "copy@acme")
      assert found.id == recipient.id
    end

    test "cancels only pending scheduled emails", %{scope: scope} do
      pending = insert(:scheduled_email, organization: scope.org, scheduled_by: scope.user)

      sent =
        insert(:scheduled_email, organization: scope.org, scheduled_by: scope.user, status: :sent)

      assert {:ok, cancelled} = Inbox.cancel_scheduled_email(scope, pending)
      assert cancelled.status == :cancelled
      assert %DateTime{} = cancelled.cancelled_at

      assert {:error, :not_pending} = Inbox.cancel_scheduled_email(scope, sent)
    end
  end

  defp insert_draft_attachment(scope, owner_id) do
    id = System.unique_integer([:positive])

    Repo.insert!(%UploadedFile{
      context: :mixed_attachment,
      tenant_id: to_string(scope.org.id),
      original_filename: "scheduled.pdf",
      storage_path: "attachments/#{scope.org.id}/#{owner_id}/#{id}.pdf",
      content_type: "application/pdf",
      byte_size: 1_024,
      sha256: String.duplicate("a", 64),
      owner_type: "email_draft",
      owner_id: owner_id,
      scan_status: :scanned
    })
  end

  # ---------------------------------------------------------------------------
  # Schema validations
  # ---------------------------------------------------------------------------

  describe "EmailIntegration.changeset/2" do
    test "requires email_address" do
      changeset = EmailIntegration.changeset(%EmailIntegration{}, %{provider: :gmail})
      assert "can't be blank" in errors_on(changeset).email_address
    end

    test "requires provider" do
      changeset = EmailIntegration.changeset(%EmailIntegration{}, %{email_address: "x@y.com"})
      assert "can't be blank" in errors_on(changeset).provider
    end

    test "rejects invalid email format" do
      changeset =
        EmailIntegration.changeset(%EmailIntegration{}, %{
          provider: :gmail,
          email_address: "not-valid"
        })

      assert "must be a valid email" in errors_on(changeset).email_address
    end

    test "rejects unknown provider" do
      changeset =
        EmailIntegration.changeset(%EmailIntegration{}, %{
          provider: :yahoo,
          email_address: "x@y.com"
        })

      assert errors_on(changeset).provider != []
    end
  end

  describe "EmailThread.changeset/2" do
    test "requires subject" do
      changeset = EmailThread.changeset(%EmailThread{}, %{})
      assert "can't be blank" in errors_on(changeset).subject
    end

    test "rejects negative revenue_at_risk" do
      changeset = EmailThread.changeset(%EmailThread{}, %{subject: "X", revenue_at_risk: "-1"})
      assert errors_on(changeset).revenue_at_risk != []
    end

    test "accepts valid category" do
      for cat <- [:lead, :customer, :support, :billing, :internal, :noise] do
        changeset = EmailThread.changeset(%EmailThread{}, %{subject: "X", category: cat})
        refute Map.has_key?(errors_on(changeset), :category)
      end
    end
  end

  describe "Email.changeset/2" do
    test "requires message_id, from, to, received_at, is_inbound" do
      changeset = Email.changeset(%Email{}, %{})

      assert "can't be blank" in errors_on(changeset).message_id
      assert "can't be blank" in errors_on(changeset).from
      assert "can't be blank" in errors_on(changeset).received_at
      assert "can't be blank" in errors_on(changeset).is_inbound
    end

    test "rejects invalid from address" do
      changeset =
        Email.changeset(%Email{}, %{
          message_id: "x",
          from: "not-email",
          to: ["a@b.com"],
          received_at: DateTime.utc_now(:second),
          is_inbound: true
        })

      assert "must be a valid email" in errors_on(changeset).from
    end
  end
end
