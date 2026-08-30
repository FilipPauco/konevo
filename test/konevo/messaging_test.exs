defmodule Konevo.MessagingTest do
  use Konevo.DataCase, async: true

  import Konevo.Factory
  import Konevo.MessagingFixtures

  alias Konevo.Accounts.Scope
  alias Konevo.Compliance
  alias Konevo.Inbox
  alias Konevo.Messaging
  alias Konevo.Messaging.{MessageDraft, MessageSent}

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
  # Drafts — list
  # ---------------------------------------------------------------------------

  describe "list_drafts/2" do
    test "returns drafts scoped to org", %{scope: scope} do
      d1 = draft_fixture(scope)
      d2 = draft_fixture(scope)

      other_scope = build_scope()
      _hidden = draft_fixture(other_scope)

      {drafts, total} = Messaging.list_drafts(scope)
      ids = Enum.map(drafts, & &1.id)

      assert d1.id in ids
      assert d2.id in ids
      assert total == 2
    end

    test "filters by status", %{scope: scope} do
      draft_fixture(scope, %{status: :pending})
      draft_fixture(scope, %{status: :approved})

      {drafts, total} = Messaging.list_drafts(scope, status: :pending)
      assert total == 1
      assert hd(drafts).status == :pending
    end

    test "filters by multiple statuses", %{scope: scope} do
      draft_fixture(scope, %{status: :pending})
      draft_fixture(scope, %{status: :approved})
      draft_fixture(scope, %{status: :sent})

      {drafts, total} = Messaging.list_drafts(scope, status: [:pending, :approved])

      assert total == 2
      assert Enum.all?(drafts, &(&1.status in [:pending, :approved]))
    end

    test "filters by ai_generated", %{scope: scope} do
      draft_fixture(scope, %{ai_generated: true})
      draft_fixture(scope, %{ai_generated: false})

      {drafts, total} = Messaging.list_drafts(scope, ai_generated: true)
      assert total == 1
      assert hd(drafts).ai_generated == true
    end

    test "paginates results", %{scope: scope} do
      Enum.each(1..5, fn _ -> draft_fixture(scope) end)

      {page1, total} = Messaging.list_drafts(scope, page: 1, per_page: 2)
      {page2, _} = Messaging.list_drafts(scope, page: 2, per_page: 2)

      assert total == 5
      assert length(page1) == 2
      refute Enum.any?(page1, fn d -> d.id in Enum.map(page2, & &1.id) end)
    end

    test "preloads a draft's source email", %{scope: scope} do
      email =
        insert(:email,
          organization: scope.org,
          thread: insert(:email_thread, organization: scope.org),
          from: "martin@example.com"
        )

      draft_fixture(scope, %{source_email_id: email.id})

      {[draft], 1} = Messaging.list_drafts(scope)

      assert draft.source_email.from == "martin@example.com"
    end
  end

  # ---------------------------------------------------------------------------
  # Drafts — create
  # ---------------------------------------------------------------------------

  describe "create_draft/2" do
    test "creates a draft with valid attrs", %{scope: scope} do
      assert {:ok, %MessageDraft{body: "Hello Jane"}} =
               Messaging.create_draft(scope, %{message_type: :email, body: "Hello Jane"})
    end

    test "associates with scope org and user", %{scope: scope} do
      {:ok, draft} = Messaging.create_draft(scope, %{message_type: :email, body: "Hi"})
      assert draft.organization_id == scope.org.id
      assert draft.created_by_id == scope.user.id
    end

    test "creates an AI-generated draft", %{scope: scope} do
      {:ok, draft} =
        Messaging.create_draft(scope, %{
          message_type: :email,
          body: "AI drafted this",
          ai_generated: true,
          ai_model_used: "gpt-4o",
          ai_confidence: 0.92,
          tone_preset: :professional
        })

      assert draft.ai_generated == true
      assert draft.ai_model_used == "gpt-4o"
      assert draft.ai_confidence == 0.92
      assert draft.tone_preset == :professional
    end

    test "returns error changeset when body missing", %{scope: scope} do
      assert {:error, %Ecto.Changeset{}} =
               Messaging.create_draft(scope, %{message_type: :email})
    end

    test "returns unauthorized for viewer" do
      scope = build_scope(:viewer)
      assert {:error, :unauthorized} = Messaging.create_draft(scope, %{})
    end
  end

  # ---------------------------------------------------------------------------
  # Drafts — update
  # ---------------------------------------------------------------------------

  describe "update_draft/3" do
    test "updates a pending draft", %{scope: scope} do
      draft = draft_fixture(scope, %{status: :pending, body: "Original"})
      assert {:ok, updated} = Messaging.update_draft(scope, draft, %{body: "Revised"})
      assert updated.body == "Revised"
    end

    test "rejects update on non-pending draft", %{scope: scope} do
      draft = draft_fixture(scope, %{status: :approved})
      assert {:error, :not_pending} = Messaging.update_draft(scope, draft, %{body: "x"})
    end
  end

  # ---------------------------------------------------------------------------
  # Drafts — approve
  # ---------------------------------------------------------------------------

  describe "approve_draft/3" do
    test "approves a pending draft", %{scope: scope} do
      draft = draft_fixture(scope, %{status: :pending})
      assert {:ok, approved} = Messaging.approve_draft(scope, draft)
      assert approved.status == :approved
      assert approved.approved_by_id == scope.user.id
      assert approved.approved_at != nil
    end

    test "records body edit when approver changes the body", %{scope: scope} do
      draft = draft_fixture(scope, %{status: :pending, body: "Original text"})
      assert {:ok, approved} = Messaging.approve_draft(scope, draft, "Edited text")
      assert approved.body == "Edited text"
      assert approved.approval_changes != nil
    end

    test "does not record approval_changes when body unchanged", %{scope: scope} do
      draft = draft_fixture(scope, %{status: :pending, body: "Same text"})
      assert {:ok, approved} = Messaging.approve_draft(scope, draft, "Same text")
      assert approved.approval_changes == nil
    end

    test "rejects approval on already-approved draft", %{scope: scope} do
      draft = draft_fixture(scope, %{status: :approved})
      assert {:error, :not_pending} = Messaging.approve_draft(scope, draft)
    end
  end

  describe "unapprove_draft/2" do
    test "returns an approved draft to review", %{scope: scope} do
      draft = draft_fixture(scope, %{status: :pending})
      {:ok, approved} = Messaging.approve_draft(scope, draft)

      assert {:ok, review_draft} = Messaging.unapprove_draft(scope, approved)
      assert review_draft.status == :pending
      assert review_draft.approved_by_id == nil
      assert review_draft.approved_at == nil
    end

    test "does not return a pending draft to review", %{scope: scope} do
      draft = draft_fixture(scope, %{status: :pending})

      assert {:error, :not_approved} = Messaging.unapprove_draft(scope, draft)
    end
  end

  describe "create_contact_and_unapprove_draft/2" do
    test "creates and links the sender contact before returning the draft to review", %{
      scope: scope
    } do
      thread = insert(:email_thread, organization: scope.org)

      insert(:email,
        organization: scope.org,
        thread: thread,
        from: "martin@example.com"
      )

      draft = draft_fixture(scope, %{status: :approved, email_thread: thread})

      assert {:ok, %{contact: contact, draft: review_draft}} =
               Messaging.create_contact_and_unapprove_draft(scope, draft)

      assert contact.email == "martin@example.com"
      assert review_draft.status == :pending
      assert review_draft.contact_id == contact.id
      assert Inbox.get_thread!(scope, thread.id).contact_id == contact.id
    end

    test "requires an inbound sender", %{scope: scope} do
      thread = insert(:email_thread, organization: scope.org)
      draft = draft_fixture(scope, %{status: :approved, email_thread: thread})

      assert {:error, :missing_sender} =
               Messaging.create_contact_and_unapprove_draft(scope, draft)
    end
  end

  # ---------------------------------------------------------------------------
  # Drafts — reject
  # ---------------------------------------------------------------------------

  describe "reject_draft/2" do
    test "rejects a pending draft", %{scope: scope} do
      draft = draft_fixture(scope, %{status: :pending})
      assert {:ok, rejected} = Messaging.reject_draft(scope, draft)
      assert rejected.status == :rejected
    end

    test "cannot reject an already-approved draft", %{scope: scope} do
      draft = draft_fixture(scope, %{status: :approved})
      assert {:error, :not_pending} = Messaging.reject_draft(scope, draft)
    end
  end

  describe "reject_all_review_drafts/1" do
    test "rejects every pending or approved draft in the current organization", %{scope: scope} do
      pending = draft_fixture(scope, %{status: :pending})
      approved = draft_fixture(scope, %{status: :approved})
      sent = draft_fixture(scope, %{status: :sent})

      other_scope = build_scope()
      other_draft = draft_fixture(other_scope, %{status: :pending})

      assert {:ok, 2} = Messaging.reject_all_review_drafts(scope)
      assert Messaging.get_draft!(scope, pending.id).status == :rejected
      assert Messaging.get_draft!(scope, approved.id).status == :rejected
      assert Messaging.get_draft!(scope, sent.id).status == :sent
      assert Messaging.get_draft!(other_scope, other_draft.id).status == :pending
    end
  end

  # ---------------------------------------------------------------------------
  # Messages sent — record_sent
  # ---------------------------------------------------------------------------

  describe "record_sent/2" do
    test "records a sent email", %{scope: scope} do
      assert {:ok, %MessageSent{message_type: :email}} =
               Messaging.record_sent(scope, %{
                 message_type: :email,
                 recipient: "jane@acme.com",
                 body: "Hi Jane",
                 status: :sent,
                 is_manual: true
               })
    end

    test "associates with scope org and user", %{scope: scope} do
      {:ok, sent} =
        Messaging.record_sent(scope, %{
          message_type: :email,
          recipient: "jane@acme.com",
          body: "Hi",
          is_manual: true
        })

      assert sent.organization_id == scope.org.id
      assert sent.sent_by_id == scope.user.id
      assert sent.sent_at != nil
    end

    test "returns error changeset when recipient missing", %{scope: scope} do
      assert {:error, %Ecto.Changeset{}} =
               Messaging.record_sent(scope, %{message_type: :email, body: "Hi"})
    end

    test "returns unauthorized for viewer" do
      scope = build_scope(:viewer)
      assert {:error, :unauthorized} = Messaging.record_sent(scope, %{})
    end
  end

  # ---------------------------------------------------------------------------
  # mark_draft_sent
  # ---------------------------------------------------------------------------

  describe "mark_draft_sent/3" do
    test "links approved draft to sent message", %{scope: scope} do
      draft = draft_fixture(scope, %{status: :approved})
      sent = sent_fixture(scope)

      assert {:ok, updated} = Messaging.mark_draft_sent(scope, draft, sent)
      assert updated.status == :sent
      assert updated.sent_message_id == sent.id
    end

    test "rejects if draft not approved", %{scope: scope} do
      draft = draft_fixture(scope, %{status: :pending})
      sent = sent_fixture(scope)

      assert {:error, :not_approved} = Messaging.mark_draft_sent(scope, draft, sent)
    end
  end

  # ---------------------------------------------------------------------------
  # send_approved_draft
  # ---------------------------------------------------------------------------

  describe "send_approved_draft/2" do
    test "records sent message after compliance passes", %{scope: scope} do
      contact =
        insert(:contact, organization: scope.org, user: scope.user, email: "ok-send@example.com")

      Compliance.record_consent(contact, :email, :manual)

      draft =
        draft_fixture(scope, %{
          status: :approved,
          contact: contact,
          subject: "Hi",
          body: "Approved body"
        })

      assert {:ok, sent_draft} = Messaging.send_approved_draft(scope, draft)
      assert sent_draft.status == :sent

      {sent_messages, 1} = Messaging.list_sent(scope, contact_id: contact.id)
      assert hd(sent_messages).recipient == "ok-send@example.com"
    end

    test "blocks send when consent is missing", %{scope: scope} do
      contact =
        insert(:contact,
          organization: scope.org,
          user: scope.user,
          email: "no-consent@example.com"
        )

      draft = draft_fixture(scope, %{status: :approved, contact: contact})

      assert {:error, :no_consent} = Messaging.send_approved_draft(scope, draft)
    end

    test "sends a human-approved reply without marketing consent", %{scope: scope} do
      contact =
        insert(:contact,
          organization: scope.org,
          user: scope.user,
          email: "manual-reply@example.com"
        )

      draft = draft_fixture(scope, %{status: :approved, contact: contact})

      assert {:ok, %{status: :sent}} =
               Messaging.send_approved_draft(scope, draft, require_consent?: false)
    end

    test "blocks send when contact is suppressed", %{scope: scope} do
      contact =
        insert(:contact, organization: scope.org, user: scope.user, email: "blocked@example.com")

      Compliance.record_consent(contact, :email, :manual)
      Compliance.suppress(scope.org, :email, "blocked@example.com", :unsubscribed)

      draft = draft_fixture(scope, %{status: :approved, contact: contact})

      assert {:error, :suppressed} = Messaging.send_approved_draft(scope, draft)
    end
  end

  # ---------------------------------------------------------------------------
  # list_sent
  # ---------------------------------------------------------------------------

  describe "list_sent/2" do
    test "returns sent messages scoped to org", %{scope: scope} do
      s1 = sent_fixture(scope)
      s2 = sent_fixture(scope)

      other_scope = build_scope()
      _hidden = sent_fixture(other_scope)

      {messages, total} = Messaging.list_sent(scope)
      ids = Enum.map(messages, & &1.id)

      assert s1.id in ids
      assert s2.id in ids
      assert total == 2
    end

    test "filters by message_type", %{scope: scope} do
      sent_fixture(scope, %{message_type: :email})
      sent_fixture(scope, %{message_type: :sms})

      {messages, total} = Messaging.list_sent(scope, message_type: :sms)
      assert total == 1
      assert hd(messages).message_type == :sms
    end

    test "filters by status", %{scope: scope} do
      sent_fixture(scope, %{status: :sent})
      sent_fixture(scope, %{status: :bounced})

      {messages, total} = Messaging.list_sent(scope, status: :bounced)
      assert total == 1
      assert hd(messages).status == :bounced
    end
  end

  # ---------------------------------------------------------------------------
  # update_delivery_status
  # ---------------------------------------------------------------------------

  describe "update_delivery_status/3" do
    test "updates status to bounced", %{scope: scope} do
      sent = sent_fixture(scope, %{status: :sent})
      assert {:ok, updated} = Messaging.update_delivery_status(sent, :bounced)
      assert updated.status == :bounced
    end

    test "records opened_at when status is opened", %{scope: scope} do
      sent = sent_fixture(scope, %{status: :sent})
      opened_at = DateTime.utc_now(:second)

      assert {:ok, updated} =
               Messaging.update_delivery_status(sent, :sent, %{opened_at: opened_at})

      assert updated.opened_at == opened_at
    end
  end

  # ---------------------------------------------------------------------------
  # pending_draft_count
  # ---------------------------------------------------------------------------

  describe "pending_draft_count/1" do
    test "counts pending AI drafts", %{scope: scope} do
      draft_fixture(scope, %{status: :pending, ai_generated: true})
      draft_fixture(scope, %{status: :pending, ai_generated: true})
      draft_fixture(scope, %{status: :approved, ai_generated: true})
      draft_fixture(scope, %{status: :pending, ai_generated: false})

      assert Messaging.pending_draft_count(scope) == 2
    end

    test "excludes other orgs", %{scope: scope} do
      other_scope = build_scope()
      draft_fixture(other_scope, %{status: :pending, ai_generated: true})

      assert Messaging.pending_draft_count(scope) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # Schema validations
  # ---------------------------------------------------------------------------

  describe "MessageDraft.changeset/2" do
    test "requires message_type and body" do
      changeset = MessageDraft.changeset(%MessageDraft{}, %{})
      assert "can't be blank" in errors_on(changeset).message_type
      assert "can't be blank" in errors_on(changeset).body
    end

    test "rejects ai_confidence outside 0.0-1.0" do
      changeset =
        MessageDraft.changeset(%MessageDraft{}, %{
          message_type: :email,
          body: "x",
          ai_confidence: 1.5
        })

      assert errors_on(changeset).ai_confidence != []
    end

    test "accepts all valid tone presets" do
      for tone <- [:professional, :casual, :urgent, :apologetic] do
        changeset =
          MessageDraft.changeset(%MessageDraft{}, %{
            message_type: :email,
            body: "x",
            tone_preset: tone
          })

        refute Map.has_key?(errors_on(changeset), :tone_preset)
      end
    end
  end

  describe "MessageSent.changeset/2" do
    test "requires message_type, recipient, body" do
      changeset = MessageSent.changeset(%MessageSent{}, %{})
      assert "can't be blank" in errors_on(changeset).message_type
      assert "can't be blank" in errors_on(changeset).recipient
      assert "can't be blank" in errors_on(changeset).body
    end

    test "rejects unknown message_type" do
      changeset =
        MessageSent.changeset(%MessageSent{}, %{
          message_type: :fax,
          recipient: "x@y.com",
          body: "hi"
        })

      assert errors_on(changeset).message_type != []
    end
  end
end
