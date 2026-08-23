defmodule Konevo.AutomationTest do
  use Konevo.DataCase, async: false

  import Ecto.Query
  import Konevo.Factory

  alias Konevo.Accounts.Scope
  alias Konevo.Automation
  alias Konevo.Automation.{Execution, Rule, Sequence, TaskApproval}
  alias Konevo.Compliance
  alias Konevo.Messaging
  alias Konevo.Messaging.MessageDraft
  alias Konevo.Repo
  alias Konevo.Tasks.Task

  defp build_scope(role \\ :owner) do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: role)
    Scope.for_user_in_org(user, org, membership)
  end

  defp sequence_for(scope, attrs \\ []) do
    insert(
      :automation_sequence,
      Keyword.merge([organization: scope.org, created_by: scope.user], attrs)
    )
  end

  defp rule_for(scope, sequence, attrs \\ []) do
    insert(:automation_rule, Keyword.merge([organization: scope.org, sequence: sequence], attrs))
  end

  defp contact_for(scope) do
    insert(:contact, organization: scope.org, user: scope.user)
  end

  defp stale_thread_for(scope, contact, sender \\ "lead@example.com") do
    thread =
      insert(:email_thread,
        organization: scope.org,
        contact: contact,
        last_inbound_at: DateTime.add(DateTime.utc_now(:second), -5, :day),
        last_outbound_at: DateTime.add(DateTime.utc_now(:second), -4, :day)
      )

    insert(:email,
      organization: scope.org,
      thread: thread,
      from: sender,
      is_inbound: true
    )

    thread
  end

  defp no_reply_sequence_for(scope, mode, config \\ %{}, rule_config \\ %{}) do
    sequence =
      sequence_for(scope,
        status: :active,
        trigger_type: :inbound_email_idle,
        trigger_config:
          Map.merge(
            %{
              "workflow_type" => "no_reply_follow_up",
              "mode" => mode,
              "idle_days" => 3,
              "excluded_senders" => []
            },
            config
          )
      )

    rule_for(scope, sequence,
      action_type: :prepare_follow_up,
      action_config: Map.merge(%{"mode" => mode}, rule_config)
    )

    sequence
  end

  defp with_ai_response(response) do
    original = Application.fetch_env!(:konevo, :ai)
    response = mock_response(response)

    Application.put_env(:konevo, :ai,
      provider: Konevo.AIMockProvider,
      models: %{
        fast: %{
          provider: :mock,
          model: "mock-fast",
          api_key: "test",
          test_pid: self(),
          response: response
        },
        standard: %{
          provider: :mock,
          model: "mock-standard",
          api_key: "test",
          test_pid: self(),
          response: response
        },
        premium: %{provider: :mock, model: "mock-premium", api_key: "test"}
      }
    )

    on_exit(fn -> Application.put_env(:konevo, :ai, original) end)
  end

  defp mock_response(response) when is_tuple(response), do: response
  defp mock_response(response) when is_binary(response), do: response
  defp mock_response(response), do: Jason.encode!(response)

  # ---------------------------------------------------------------------------
  # create_sequence/2
  # ---------------------------------------------------------------------------

  describe "create_sequence/2" do
    test "creates a sequence in draft status" do
      scope = build_scope()

      assert {:ok, %Sequence{status: :draft, trigger_type: :manual}} =
               Automation.create_sequence(scope, %{name: "Welcome series", trigger_type: :manual})
    end

    test "scopes sequence to org" do
      scope = build_scope()

      {:ok, seq} = Automation.create_sequence(scope, %{name: "Test", trigger_type: :manual})
      assert seq.organization_id == scope.org.id
      assert seq.created_by_id == scope.user.id
    end

    test "requires name and trigger_type" do
      scope = build_scope()

      assert {:error, changeset} = Automation.create_sequence(scope, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.trigger_type
    end

    test "returns unauthorized for viewer" do
      scope = build_scope(:viewer)

      assert {:error, :unauthorized} =
               Automation.create_sequence(scope, %{name: "x", trigger_type: :manual})
    end
  end

  # ---------------------------------------------------------------------------
  # list_sequences/2
  # ---------------------------------------------------------------------------

  describe "list_sequences/2" do
    test "returns sequences scoped to org" do
      scope = build_scope()
      other_scope = build_scope()
      s1 = sequence_for(scope)
      s2 = sequence_for(scope)
      _hidden = sequence_for(other_scope)

      seqs = Automation.list_sequences(scope)
      ids = Enum.map(seqs, & &1.id)

      assert s1.id in ids
      assert s2.id in ids
      assert length(seqs) == 2
    end

    test "filters by status" do
      scope = build_scope()
      _draft = sequence_for(scope, status: :draft)
      _active = sequence_for(scope, status: :active)

      drafts = Automation.list_sequences(scope, status: :draft)
      assert Enum.all?(drafts, &(&1.status == :draft))
    end
  end

  # ---------------------------------------------------------------------------
  # update_sequence/3
  # ---------------------------------------------------------------------------

  describe "update_sequence/3" do
    test "updates name and description" do
      scope = build_scope()
      seq = sequence_for(scope)

      assert {:ok, updated} =
               Automation.update_sequence(scope, seq, %{name: "New name", description: "Desc"})

      assert updated.name == "New name"
    end

    test "returns unauthorized for viewer" do
      scope = build_scope(:viewer)
      seq = sequence_for(scope)

      assert {:error, :unauthorized} = Automation.update_sequence(scope, seq, %{name: "x"})
    end
  end

  # ---------------------------------------------------------------------------
  # activate / pause / archive sequence
  # ---------------------------------------------------------------------------

  describe "activate_sequence/2" do
    test "sets status to active" do
      scope = build_scope()
      seq = sequence_for(scope, status: :draft)

      assert {:ok, %Sequence{status: :active, activated_at: %DateTime{}}} =
               Automation.activate_sequence(scope, seq)
    end

    test "prevents more than one active workflow of the same type" do
      scope = build_scope()

      _active =
        sequence_for(scope,
          status: :active,
          trigger_config: %{"workflow_type" => "inbound_email_task"}
        )

      paused =
        sequence_for(scope,
          status: :paused,
          trigger_config: %{"workflow_type" => "inbound_email_task"}
        )

      assert {:error, :workflow_type_already_active} = Automation.activate_sequence(scope, paused)
      assert Repo.reload!(paused).status == :paused
    end
  end

  describe "pause_sequence/2" do
    test "sets status to paused" do
      scope = build_scope()
      seq = sequence_for(scope, status: :active)

      assert {:ok, %Sequence{status: :paused}} = Automation.pause_sequence(scope, seq)
    end
  end

  describe "archive_sequence/2" do
    test "sets status to archived" do
      scope = build_scope()
      seq = sequence_for(scope, status: :paused)

      assert {:ok, %Sequence{status: :archived}} = Automation.archive_sequence(scope, seq)
    end
  end

  # ---------------------------------------------------------------------------
  # delete_sequence/2
  # ---------------------------------------------------------------------------

  describe "delete_sequence/2" do
    test "deletes a draft sequence" do
      scope = build_scope()
      seq = sequence_for(scope, status: :draft)

      assert {:ok, _} = Automation.delete_sequence(scope, seq)
      assert_raise Ecto.NoResultsError, fn -> Automation.get_sequence!(scope, seq.id) end
    end

    test "deletes an archived sequence" do
      scope = build_scope()
      seq = sequence_for(scope, status: :archived)

      assert {:ok, _} = Automation.delete_sequence(scope, seq)
    end

    test "refuses to delete an active sequence" do
      scope = build_scope()
      seq = sequence_for(scope, status: :active)

      assert {:error, :cannot_delete_active_sequence} = Automation.delete_sequence(scope, seq)
    end

    test "refuses to delete a paused sequence" do
      scope = build_scope()
      seq = sequence_for(scope, status: :paused)

      assert {:error, :cannot_delete_active_sequence} = Automation.delete_sequence(scope, seq)
    end
  end

  # ---------------------------------------------------------------------------
  # add_rule/3
  # ---------------------------------------------------------------------------

  describe "add_rule/3" do
    test "creates a rule attached to the sequence" do
      scope = build_scope()
      seq = sequence_for(scope)

      assert {:ok, %Rule{action_type: :send_email, position: 0}} =
               Automation.add_rule(scope, seq, %{action_type: :send_email})
    end

    test "auto-increments position" do
      scope = build_scope()
      seq = sequence_for(scope)

      {:ok, r1} = Automation.add_rule(scope, seq, %{action_type: :send_email})
      {:ok, r2} = Automation.add_rule(scope, seq, %{action_type: :wait})

      assert r1.position == 0
      assert r2.position == 1
    end

    test "accepts delay_seconds and action_config" do
      scope = build_scope()
      seq = sequence_for(scope)

      {:ok, rule} =
        Automation.add_rule(scope, seq, %{
          action_type: :send_email,
          delay_seconds: 86_400,
          action_config: %{subject: "Follow up", body: "Hey!"}
        })

      assert rule.delay_seconds == 86_400
      assert rule.action_config[:subject] == "Follow up"
    end

    test "accepts string-keyed form params without mixing position key types" do
      scope = build_scope()
      seq = sequence_for(scope)

      assert {:ok, %Rule{action_type: :prepare_task, position: 0} = rule} =
               Automation.add_rule(scope, seq, %{
                 "action_type" => "prepare_task",
                 "delay_seconds" => 0,
                 "action_config" => %{
                   "title" => "Review inbound lead email",
                   "instructions" => "Extract only concrete tasks."
                 }
               })

      assert rule.action_config["instructions"] == "Extract only concrete tasks."
    end

    test "requires action_type" do
      scope = build_scope()
      seq = sequence_for(scope)

      assert {:error, changeset} = Automation.add_rule(scope, seq, %{})
      assert "can't be blank" in errors_on(changeset).action_type
    end
  end

  # ---------------------------------------------------------------------------
  # list_rules/1
  # ---------------------------------------------------------------------------

  describe "list_rules/1" do
    test "returns rules ordered by position" do
      scope = build_scope()
      seq = sequence_for(scope)
      r1 = rule_for(scope, seq, position: 0, action_type: :send_email)
      r2 = rule_for(scope, seq, position: 1, action_type: :wait)
      r3 = rule_for(scope, seq, position: 2, action_type: :create_task)

      rules = Automation.list_rules(seq)
      assert Enum.map(rules, & &1.id) == [r1.id, r2.id, r3.id]
    end

    test "returns empty list for sequence with no rules" do
      scope = build_scope()
      seq = sequence_for(scope)

      assert Automation.list_rules(seq) == []
    end
  end

  # ---------------------------------------------------------------------------
  # update_rule/3 and delete_rule/2
  # ---------------------------------------------------------------------------

  describe "update_rule/3" do
    test "updates delay_seconds and action_config" do
      scope = build_scope()
      seq = sequence_for(scope)
      rule = rule_for(scope, seq)

      assert {:ok, updated} = Automation.update_rule(scope, rule, %{delay_seconds: 3600})
      assert updated.delay_seconds == 3600
    end
  end

  describe "delete_rule/2" do
    test "removes the rule" do
      scope = build_scope()
      seq = sequence_for(scope)
      rule = rule_for(scope, seq)

      assert {:ok, _} = Automation.delete_rule(scope, rule)
      assert Automation.list_rules(seq) == []
    end
  end

  # ---------------------------------------------------------------------------
  # enroll_contact/3
  # ---------------------------------------------------------------------------

  describe "enroll_contact/3" do
    test "creates a pending execution" do
      scope = build_scope()
      seq = sequence_for(scope)
      contact = contact_for(scope)

      assert {:ok, %Execution{status: :pending}} =
               Automation.enroll_contact(scope, seq, contact)
    end

    test "is idempotent — returns existing active execution" do
      scope = build_scope()
      seq = sequence_for(scope)
      contact = contact_for(scope)

      {:ok, first} = Automation.enroll_contact(scope, seq, contact)
      {:ok, second} = Automation.enroll_contact(scope, seq, contact)

      assert first.id == second.id
    end

    test "allows re-enrollment after completion" do
      scope = build_scope()
      seq = sequence_for(scope)
      contact = contact_for(scope)

      {:ok, exec} = Automation.enroll_contact(scope, seq, contact)
      Automation.complete_execution(exec)

      {:ok, new_exec} = Automation.enroll_contact(scope, seq, contact)
      refute exec.id == new_exec.id
    end

    test "member can enroll contacts" do
      scope = build_scope(:member)
      seq = sequence_for(scope)
      contact = contact_for(scope)

      assert {:ok, _} = Automation.enroll_contact(scope, seq, contact)
    end
  end

  # ---------------------------------------------------------------------------
  # advance / complete / fail / cancel execution
  # ---------------------------------------------------------------------------

  describe "advance_execution/2" do
    test "sets status to running and updates current_rule" do
      scope = build_scope()
      seq = sequence_for(scope)
      contact = contact_for(scope)
      rule = rule_for(scope, seq)

      {:ok, exec} = Automation.enroll_contact(scope, seq, contact)
      assert {:ok, advanced} = Automation.advance_execution(exec, rule)

      assert advanced.status == :running
      assert advanced.current_rule_id == rule.id
    end
  end

  describe "complete_execution/1" do
    test "sets status to completed with completed_at" do
      scope = build_scope()
      seq = sequence_for(scope)
      contact = contact_for(scope)

      {:ok, exec} = Automation.enroll_contact(scope, seq, contact)
      assert {:ok, done} = Automation.complete_execution(exec)

      assert done.status == :completed
      assert done.completed_at != nil
      assert done.current_rule_id == nil
    end
  end

  describe "fail_execution/2" do
    test "sets status to failed with error message" do
      scope = build_scope()
      seq = sequence_for(scope)
      contact = contact_for(scope)

      {:ok, exec} = Automation.enroll_contact(scope, seq, contact)
      assert {:ok, failed} = Automation.fail_execution(exec, "Email delivery failed")

      assert failed.status == :failed
      assert failed.error_message == "Email delivery failed"
    end
  end

  describe "cancel_execution/1" do
    test "sets status to cancelled" do
      scope = build_scope()
      seq = sequence_for(scope)
      contact = contact_for(scope)

      {:ok, exec} = Automation.enroll_contact(scope, seq, contact)
      assert {:ok, cancelled} = Automation.cancel_execution(exec)

      assert cancelled.status == :cancelled
    end
  end

  describe "cancel_active_executions_for_contact_id/2" do
    test "stops pending and running executions after inbound reply" do
      scope = build_scope()
      seq = sequence_for(scope)
      contact = contact_for(scope)
      {:ok, exec} = Automation.enroll_contact(scope, seq, contact)

      assert {:ok, 1} =
               Automation.cancel_active_executions_for_contact_id(scope.org.id, contact.id)

      assert Repo.reload!(exec).status == :cancelled
    end
  end

  describe "prepare_stale_inbound_follow_ups/3" do
    test "creates a pending approval draft for unanswered outbound replies" do
      scope = build_scope()
      contact = contact_for(scope)

      thread =
        insert(:email_thread,
          organization: scope.org,
          contact: contact,
          last_inbound_at: DateTime.add(DateTime.utc_now(:second), -5, :day),
          last_outbound_at: DateTime.add(DateTime.utc_now(:second), -4, :day)
        )

      assert {:ok, [%MessageDraft{} = draft], []} =
               Automation.prepare_stale_inbound_follow_ups(scope, 3, %{
                 subject: "Checking in",
                 body: "Still interested?"
               })

      assert draft.status == :pending
      assert draft.contact_id == contact.id
      assert draft.email_thread_id == thread.id
      assert draft.subject == "Checking in"
    end

    test "skips threads when the customer replied after the outbound email" do
      scope = build_scope()
      contact = contact_for(scope)
      inbound_at = DateTime.add(DateTime.utc_now(:second), -4, :day)

      insert(:email_thread,
        organization: scope.org,
        contact: contact,
        last_inbound_at: inbound_at,
        last_outbound_at: DateTime.add(inbound_at, -1, :day)
      )

      assert {:ok, [], []} = Automation.prepare_stale_inbound_follow_ups(scope, 3)
    end

    test "treats zero days as the one-day minimum" do
      scope = build_scope()
      contact = contact_for(scope)

      insert(:email_thread,
        organization: scope.org,
        contact: contact,
        last_inbound_at: DateTime.add(DateTime.utc_now(:second), -7, :minute),
        last_outbound_at: DateTime.add(DateTime.utc_now(:second), -6, :minute)
      )

      assert {:ok, [], []} = Automation.prepare_stale_inbound_follow_ups(scope, 0)
    end
  end

  describe "prepare_active_no_reply_follow_ups/1" do
    test "manual workflow creates a pending follow-up draft" do
      scope = build_scope()

      contact =
        insert(:contact,
          organization: scope.org,
          user: scope.user,
          email: "manual-follow-up@example.com"
        )

      thread =
        insert(:email_thread,
          organization: scope.org,
          contact: contact,
          last_inbound_at: DateTime.add(DateTime.utc_now(:second), -5, :day),
          last_outbound_at: DateTime.add(DateTime.utc_now(:second), -4, :day)
        )

      insert(:email,
        organization: scope.org,
        thread: thread,
        from: "lead@example.com",
        is_inbound: true
      )

      sequence =
        sequence_for(scope,
          status: :active,
          trigger_type: :inbound_email_idle,
          trigger_config: %{
            "workflow_type" => "no_reply_follow_up",
            "mode" => "manual",
            "idle_days" => 3,
            "excluded_senders" => []
          }
        )

      rule_for(scope, sequence,
        action_type: :prepare_follow_up,
        action_config: %{"subject" => "Checking in", "body" => "Can I help?", "mode" => "manual"}
      )

      assert {:ok, [%MessageDraft{} = draft], []} =
               Automation.prepare_active_no_reply_follow_ups(scope)

      assert draft.status == :pending
      assert draft.subject == "Checking in"
      assert draft.body == "Can I help?"
      assert draft.email_thread_id == thread.id
    end

    test "automatic workflow sends a follow-up without a separate consent record" do
      scope = build_scope()

      contact =
        insert(:contact,
          organization: scope.org,
          user: scope.user,
          email: "automatic-follow-up@example.com"
        )

      thread =
        insert(:email_thread,
          organization: scope.org,
          contact: contact,
          last_inbound_at: DateTime.add(DateTime.utc_now(:second), -5, :day),
          last_outbound_at: DateTime.add(DateTime.utc_now(:second), -4, :day)
        )

      insert(:email,
        organization: scope.org,
        thread: thread,
        from: "lead@example.com",
        is_inbound: true
      )

      sequence =
        sequence_for(scope,
          status: :active,
          trigger_type: :inbound_email_idle,
          trigger_config: %{
            "workflow_type" => "no_reply_follow_up",
            "mode" => "automatic",
            "idle_days" => 3,
            "excluded_senders" => []
          }
        )

      rule_for(scope, sequence,
        action_type: :prepare_follow_up,
        action_config: %{
          "subject" => "Automatic follow-up",
          "body" => "Are you still interested?"
        }
      )

      assert {:ok, [%MessageDraft{} = draft], []} =
               Automation.prepare_active_no_reply_follow_ups(scope)

      assert draft.status == :sent
      {sent_messages, 1} = Messaging.list_sent(scope, contact_id: contact.id)
      assert hd(sent_messages).is_automation

      assert {:ok, [], []} = Automation.prepare_active_no_reply_follow_ups(scope)
    end

    test "starts a fresh one-day window after a newer outbound reply" do
      scope = build_scope()
      contact = insert(:contact, organization: scope.org, user: scope.user)
      thread = stale_thread_for(scope, contact)
      no_reply_sequence_for(scope, "manual", %{"idle_days" => 1})

      assert {:ok, [first_draft], []} = Automation.prepare_active_no_reply_follow_ups(scope)

      newer_outbound_at = DateTime.add(first_draft.inserted_at, 1, :second)

      thread
      |> Ecto.Changeset.change(last_outbound_at: newer_outbound_at)
      |> Repo.update!()

      assert {:ok, [], []} = Automation.prepare_active_no_reply_follow_ups(scope)
    end

    test "automatic workflow sends a follow-up when consent is not recorded" do
      scope = build_scope()

      contact =
        insert(:contact,
          organization: scope.org,
          user: scope.user,
          email: "missing-consent-follow-up@example.com"
        )

      thread =
        insert(:email_thread,
          organization: scope.org,
          contact: contact,
          last_inbound_at: DateTime.add(DateTime.utc_now(:second), -5, :day),
          last_outbound_at: DateTime.add(DateTime.utc_now(:second), -4, :day)
        )

      insert(:email,
        organization: scope.org,
        thread: thread,
        from: "lead@example.com",
        is_inbound: true
      )

      sequence =
        sequence_for(scope,
          status: :active,
          trigger_type: :inbound_email_idle,
          trigger_config: %{
            "workflow_type" => "no_reply_follow_up",
            "mode" => "automatic",
            "idle_days" => 3,
            "excluded_senders" => []
          }
        )

      rule_for(scope, sequence, action_type: :prepare_follow_up)

      assert {:ok, [%MessageDraft{} = draft], []} =
               Automation.prepare_active_no_reply_follow_ups(scope)

      assert draft.status == :sent
      {sent_messages, 1} = Messaging.list_sent(scope, contact_id: contact.id)
      assert hd(sent_messages).is_automation
    end

    test "manual workflow draft can be approved and sent" do
      scope = build_scope()

      contact =
        insert(:contact,
          organization: scope.org,
          user: scope.user,
          email: "manual-delivery@example.com"
        )

      Compliance.record_consent(contact, :email, :manual)
      thread = stale_thread_for(scope, contact)

      no_reply_sequence_for(scope, "manual", %{}, %{
        "subject" => "Checking in",
        "body" => "Can I help?"
      })

      assert {:ok, [draft], []} = Automation.prepare_active_no_reply_follow_ups(scope)
      assert {:ok, approved} = Messaging.approve_draft(scope, draft)
      assert {:ok, sent} = Messaging.send_approved_draft(scope, approved)

      assert sent.status == :sent
      assert sent.email_thread_id == thread.id
      {sent_messages, 1} = Messaging.list_sent(scope, contact_id: contact.id)
      assert hd(sent_messages).is_automation
    end

    test "manual workflow draft can be rejected without sending" do
      scope = build_scope()

      contact =
        insert(:contact,
          organization: scope.org,
          user: scope.user,
          email: "manual-rejection@example.com"
        )

      thread = stale_thread_for(scope, contact)
      no_reply_sequence_for(scope, "manual")

      assert {:ok, [draft], []} = Automation.prepare_active_no_reply_follow_ups(scope)
      assert {:ok, rejected} = Messaging.reject_draft(scope, draft)

      assert rejected.status == :rejected
      {_sent_messages, 0} = Messaging.list_sent(scope, contact_id: contact.id)
      assert rejected.email_thread_id == thread.id
    end

    test "automatic workflow does not persist a draft for a suppressed contact" do
      scope = build_scope()

      contact =
        insert(:contact,
          organization: scope.org,
          user: scope.user,
          email: "suppressed-follow-up@example.com"
        )

      Compliance.record_consent(contact, :email, :manual)
      Compliance.suppress(scope.org, :email, contact.email, :unsubscribed)
      thread = stale_thread_for(scope, contact)
      no_reply_sequence_for(scope, "automatic")

      assert {:ok, [], [{:error, [{:error, :suppressed}]}]} =
               Automation.prepare_active_no_reply_follow_ups(scope)

      refute Repo.get_by(MessageDraft, organization_id: scope.org.id, email_thread_id: thread.id)
    end

    test "creates one follow-up when multiple active workflows match a thread" do
      scope = build_scope()
      thread = stale_thread_for(scope, contact_for(scope))

      no_reply_sequence_for(scope, "manual", %{}, %{"subject" => "First"})
      no_reply_sequence_for(scope, "manual", %{}, %{"subject" => "Second"})

      assert {:ok, [_draft], []} = Automation.prepare_active_no_reply_follow_ups(scope)

      assert Repo.aggregate(MessageDraft, :count, :id) == 1
      assert Repo.get_by(MessageDraft, email_thread_id: thread.id)
    end

    test "skips inactive workflows and excluded senders" do
      scope = build_scope()
      contact = contact_for(scope)

      thread =
        insert(:email_thread,
          organization: scope.org,
          contact: contact,
          last_inbound_at: DateTime.add(DateTime.utc_now(:second), -5, :day),
          last_outbound_at: DateTime.add(DateTime.utc_now(:second), -4, :day)
        )

      insert(:email,
        organization: scope.org,
        thread: thread,
        from: "noreply@vendor.example",
        is_inbound: true
      )

      active =
        sequence_for(scope,
          status: :active,
          trigger_type: :inbound_email_idle,
          trigger_config: %{
            "workflow_type" => "no_reply_follow_up",
            "mode" => "manual",
            "idle_days" => 3,
            "excluded_senders" => ["noreply@*"]
          }
        )

      inactive =
        sequence_for(scope,
          status: :draft,
          trigger_type: :inbound_email_idle,
          trigger_config: %{
            "workflow_type" => "no_reply_follow_up",
            "mode" => "manual",
            "idle_days" => 3,
            "excluded_senders" => []
          }
        )

      rule_for(scope, active, action_type: :prepare_follow_up)
      rule_for(scope, inactive, action_type: :prepare_follow_up)

      assert {:ok, [], []} = Automation.prepare_active_no_reply_follow_ups(scope)
      refute Repo.get_by(MessageDraft, organization_id: scope.org.id, email_thread_id: thread.id)
    end
  end

  describe "prepare_inbound_email_replies/2" do
    test "queues one AI reply draft for review even with an automatic legacy config" do
      with_ai_response("<p>Hello,</p><p>Thank you for your email.</p><p>Best regards,</p>")
      scope = build_scope()

      contact =
        insert(:contact, organization: scope.org, user: scope.user, email: "buyer@example.com")

      thread =
        insert(:email_thread,
          organization: scope.org,
          contact: contact,
          subject: "Product question"
        )

      sequence =
        sequence_for(scope,
          status: :active,
          activated_at: DateTime.add(DateTime.utc_now(:second), -1, :second),
          trigger_type: :inbound_email_received,
          trigger_config: %{"workflow_type" => "inbound_email_reply", "mode" => "automatic"}
        )

      rule_for(scope, sequence,
        action_type: :prepare_reply,
        action_config: %{"mode" => "automatic"}
      )

      email =
        insert(:email,
          organization: scope.org,
          thread: thread,
          from: "buyer@example.com",
          subject: "Product question",
          body: "Can you help me?",
          is_inbound: true
        )

      assert {:ok, [%MessageDraft{} = draft], []} =
               Automation.prepare_inbound_email_replies(scope, email)

      assert draft.status == :pending
      assert draft.ai_generated
      assert draft.source_email_id == email.id
      assert draft.subject == "Re: Product question"
      assert draft.body == "Hello,\n\nThank you for your email.\n\nBest regards,"
      assert {:ok, [], []} = Automation.prepare_inbound_email_replies(scope, email)
    end

    test "ignores emails received before the workflow was activated" do
      scope = build_scope()
      thread = insert(:email_thread, organization: scope.org, subject: "Earlier email")

      email =
        insert(:email,
          organization: scope.org,
          thread: thread,
          is_inbound: true,
          received_at: DateTime.add(DateTime.utc_now(:second), -5, :minute)
        )

      sequence =
        sequence_for(scope,
          status: :active,
          activated_at: DateTime.utc_now(:second),
          trigger_type: :inbound_email_received,
          trigger_config: %{"workflow_type" => "inbound_email_reply", "mode" => "manual"}
        )

      rule_for(scope, sequence, action_type: :prepare_reply, action_config: %{"mode" => "manual"})

      assert {:ok, [], []} = Automation.prepare_inbound_email_replies(scope, email)
      refute Repo.get_by(MessageDraft, organization_id: scope.org.id, source_email_id: email.id)
    end
  end

  describe "prepare_inbound_email_tasks/2" do
    test "reports AI failures without creating tasks or approvals" do
      with_ai_response({:error, :provider_unavailable})
      scope = build_scope()

      sequence =
        sequence_for(scope,
          status: :active,
          trigger_type: :inbound_email_received,
          trigger_config: %{"workflow_type" => "inbound_email_task", "mode" => "automatic"}
        )

      rule_for(scope, sequence, action_type: :prepare_task)

      email =
        insert(:email,
          organization: scope.org,
          thread: insert(:email_thread, organization: scope.org),
          is_inbound: true
        )

      assert {:ok, [], [{:error, :provider_unavailable}]} =
               Automation.prepare_inbound_email_tasks(scope, email)

      refute Repo.get_by(Task, organization_id: scope.org.id, source_email_id: email.id)
      refute Repo.get_by(TaskApproval, organization_id: scope.org.id, email_id: email.id)
    end

    test "ignores inbound emails when no active workflow exists" do
      scope = build_scope()

      sequence_for(scope,
        status: :paused,
        trigger_type: :inbound_email_received,
        trigger_config: %{"workflow_type" => "inbound_email_task", "mode" => "automatic"}
      )

      email =
        insert(:email,
          organization: scope.org,
          thread: insert(:email_thread, organization: scope.org),
          is_inbound: true
        )

      assert {:ok, [], []} = Automation.prepare_inbound_email_tasks(scope, email)
      refute Repo.get_by(Task, organization_id: scope.org.id, source_email_id: email.id)
    end

    test "automatic workflow creates extracted tasks from an inbound email" do
      with_ai_response(%{
        tasks: [
          %{
            title: "Prepare proposal",
            description: "Lead asked for proposal details.",
            due_date: "2026-08-04",
            priority: "high",
            confidence: 0.91
          }
        ]
      })

      scope = build_scope()
      company = insert(:company, organization: scope.org, user: scope.user, name: "Acme")
      contact = insert(:contact, organization: scope.org, user: scope.user, company: company)

      sequence =
        sequence_for(scope,
          status: :active,
          trigger_type: :inbound_email_received,
          trigger_config: %{"workflow_type" => "inbound_email_task", "mode" => "automatic"}
        )

      rule_for(scope, sequence,
        action_type: :prepare_task,
        action_config: %{"instructions" => "Extract tasks for sales follow-up."}
      )

      thread = insert(:email_thread, organization: scope.org, contact: contact)

      email =
        insert(:email,
          organization: scope.org,
          thread: thread,
          subject: "Can you send a proposal?",
          body: "Please send the proposal next week.",
          is_inbound: true
        )

      assert {:ok, [%Task{} = task], []} = Automation.prepare_inbound_email_tasks(scope, email)

      assert task.title == "Prepare proposal"
      assert task.priority == :high
      assert task.contact_id == contact.id
      assert task.company_id == company.id
      assert task.source_email_id == email.id
      assert task.source_thread_id == thread.id
      assert task.parent_task_id

      parent = Konevo.Tasks.get_task!(scope, task.parent_task_id)
      assert parent.title == "Company - Acme"
      assert_received {:ai_complete, :entity_extraction, _messages}
    end

    test "automatic workflow creates every extracted task from an inbound email" do
      with_ai_response(%{
        tasks: [
          %{title: "Call lead", confidence: 0.8},
          %{title: "Send pricing", priority: "high", confidence: 0.9}
        ]
      })

      scope = build_scope()

      sequence =
        sequence_for(scope,
          status: :active,
          trigger_type: :inbound_email_received,
          trigger_config: %{"workflow_type" => "inbound_email_task", "mode" => "automatic"}
        )

      rule_for(scope, sequence, action_type: :prepare_task)

      email =
        insert(:email,
          organization: scope.org,
          thread: insert(:email_thread, organization: scope.org),
          is_inbound: true
        )

      assert {:ok, [%Task{}, %Task{}] = tasks, []} =
               Automation.prepare_inbound_email_tasks(scope, email)

      assert Enum.map(tasks, & &1.title) == ["Call lead", "Send pricing"]
      assert Enum.all?(tasks, &(&1.source_email_id == email.id))
    end

    test "manual workflow queues extracted tasks for approval without creating tasks" do
      with_ai_response(%{
        tasks: [
          %{title: "Call lead", confidence: 0.8},
          %{title: "Send pricing", priority: "high", confidence: 0.9}
        ]
      })

      scope = build_scope()

      sequence =
        sequence_for(scope,
          status: :active,
          trigger_type: :inbound_email_received,
          trigger_config: %{"workflow_type" => "inbound_email_task", "mode" => "manual"}
        )

      rule_for(scope, sequence,
        action_type: :prepare_task,
        action_config: %{"title" => "Review hot inbound lead"}
      )

      email =
        insert(:email,
          organization: scope.org,
          thread: insert(:email_thread, organization: scope.org),
          is_inbound: true
        )

      assert {:ok, [%TaskApproval{}, %TaskApproval{}] = approvals, []} =
               Automation.prepare_inbound_email_tasks(scope, email)

      assert Enum.map(approvals, & &1.title) == ["Call lead", "Send pricing"]
      assert Enum.all?(approvals, &(&1.status == :pending))
      assert Enum.all?(approvals, &(&1.email_id == email.id))
      refute Repo.get_by(Task, organization_id: scope.org.id, source_email_id: email.id)
    end

    test "approving a task approval creates the task" do
      with_ai_response(%{tasks: [%{title: "Call lead", confidence: 0.8}]})

      scope = build_scope()

      sequence =
        sequence_for(scope,
          status: :active,
          trigger_type: :inbound_email_received,
          trigger_config: %{"workflow_type" => "inbound_email_task", "mode" => "manual"}
        )

      rule_for(scope, sequence, action_type: :prepare_task)

      email =
        insert(:email,
          organization: scope.org,
          thread: insert(:email_thread, organization: scope.org),
          is_inbound: true
        )

      {:ok, [approval], []} = Automation.prepare_inbound_email_tasks(scope, email)

      assert {:ok, %Task{} = task} =
               Automation.approve_task_approval(scope, approval, %{
                 "title" => "Call lead today",
                 "description" => "Confirmed by reviewer.",
                 "due_date" => "2026-08-05T17:00",
                 "priority" => "high"
               })

      assert task.title == "Call lead today"
      assert task.priority == :high
      assert task.source_email_id == email.id

      approval = Repo.reload!(approval)
      assert approval.status == :approved
      assert approval.created_task_id == task.id
    end

    test "rejecting a task approval creates no task" do
      with_ai_response(%{tasks: [%{title: "Call lead", confidence: 0.8}]})
      scope = build_scope()

      sequence =
        sequence_for(scope,
          status: :active,
          trigger_type: :inbound_email_received,
          trigger_config: %{"workflow_type" => "inbound_email_task", "mode" => "manual"}
        )

      rule_for(scope, sequence, action_type: :prepare_task)

      email =
        insert(:email,
          organization: scope.org,
          thread: insert(:email_thread, organization: scope.org),
          is_inbound: true
        )

      {:ok, [approval], []} = Automation.prepare_inbound_email_tasks(scope, email)

      assert {:ok, rejected} = Automation.reject_task_approval(scope, approval)
      assert rejected.status == :rejected
      refute Repo.get_by(Task, organization_id: scope.org.id, source_email_id: email.id)
    end

    test "does not create duplicate work for the same source email" do
      with_ai_response(%{tasks: [%{title: "Follow up", confidence: 0.8}]})

      scope = build_scope()

      sequence =
        sequence_for(scope,
          status: :active,
          trigger_type: :inbound_email_received,
          trigger_config: %{"workflow_type" => "inbound_email_task", "mode" => "automatic"}
        )

      rule_for(scope, sequence, action_type: :prepare_task)

      email =
        insert(:email,
          organization: scope.org,
          thread: insert(:email_thread, organization: scope.org),
          is_inbound: true
        )

      assert {:ok, [%Task{}], []} = Automation.prepare_inbound_email_tasks(scope, email)
      assert {:ok, [], []} = Automation.prepare_inbound_email_tasks(scope, email)
    end

    test "does not create duplicate approvals for the same source email" do
      with_ai_response(%{tasks: [%{title: "Follow up", confidence: 0.8}]})

      scope = build_scope()

      sequence =
        sequence_for(scope,
          status: :active,
          trigger_type: :inbound_email_received,
          trigger_config: %{"workflow_type" => "inbound_email_task", "mode" => "manual"}
        )

      rule_for(scope, sequence, action_type: :prepare_task)

      email =
        insert(:email,
          organization: scope.org,
          thread: insert(:email_thread, organization: scope.org),
          is_inbound: true
        )

      assert {:ok, [%TaskApproval{}], []} = Automation.prepare_inbound_email_tasks(scope, email)
      assert {:ok, [], []} = Automation.prepare_inbound_email_tasks(scope, email)
    end
  end

  describe "expire_pending_approvals/1" do
    test "rejects only pending approvals older than the organization retention period" do
      scope = build_scope()
      now = ~U[2026-08-14 12:00:00Z]

      assert {:ok, _organization} =
               Automation.update_approval_expiry(scope, %{"approval_expiry_days" => "1"})

      email =
        insert(:email,
          organization: scope.org,
          thread: insert(:email_thread, organization: scope.org),
          is_inbound: true
        )

      expired_approval =
        %TaskApproval{organization_id: scope.org.id}
        |> TaskApproval.changeset(%{
          email_id: email.id,
          email_thread_id: email.thread_id,
          title: "Expired approval",
          due_date: DateTime.add(now, 1, :day),
          priority: :normal,
          confidence: 0.9
        })
        |> Repo.insert!()

      expired_draft =
        insert(:message_draft,
          organization: scope.org,
          created_by: scope.user,
          status: :pending
        )

      fresh_draft =
        insert(:message_draft,
          organization: scope.org,
          created_by: scope.user,
          status: :pending
        )

      stale_at = DateTime.add(now, -2, :day)
      recent_at = DateTime.add(now, -12, :hour)

      Repo.update_all(
        from(approval in TaskApproval, where: approval.id == ^expired_approval.id),
        set: [inserted_at: stale_at, updated_at: stale_at]
      )

      Repo.update_all(
        from(draft in MessageDraft, where: draft.id == ^expired_draft.id),
        set: [inserted_at: stale_at, updated_at: stale_at]
      )

      Repo.update_all(
        from(draft in MessageDraft, where: draft.id == ^fresh_draft.id),
        set: [inserted_at: recent_at, updated_at: recent_at]
      )

      assert {:ok, %{tasks: 1, drafts: 1}} = Automation.expire_pending_approvals(now)
      assert Repo.reload!(expired_approval).status == :rejected
      assert Repo.reload!(expired_draft).status == :rejected
      assert Repo.reload!(fresh_draft).status == :pending

      assert {:ok, %{tasks: 0, drafts: 0}} = Automation.expire_pending_approvals(now)
    end
  end

  # ---------------------------------------------------------------------------
  # list_executions/3
  # ---------------------------------------------------------------------------

  describe "list_executions/3" do
    test "returns executions for a sequence" do
      scope = build_scope()
      seq = sequence_for(scope)
      c1 = contact_for(scope)
      c2 = contact_for(scope)

      {:ok, e1} = Automation.enroll_contact(scope, seq, c1)
      {:ok, e2} = Automation.enroll_contact(scope, seq, c2)

      execs = Automation.list_executions(scope, seq)
      ids = Enum.map(execs, & &1.id)

      assert e1.id in ids
      assert e2.id in ids
    end

    test "filters by status" do
      scope = build_scope()
      seq = sequence_for(scope)
      c1 = contact_for(scope)
      c2 = contact_for(scope)

      {:ok, pending} = Automation.enroll_contact(scope, seq, c1)
      {:ok, exec2} = Automation.enroll_contact(scope, seq, c2)
      Automation.complete_execution(exec2)

      results = Automation.list_executions(scope, seq, status: :pending)
      assert Enum.all?(results, &(&1.status == :pending))
      ids = Enum.map(results, & &1.id)
      assert pending.id in ids
    end
  end

  # ---------------------------------------------------------------------------
  # execution_counts/1
  # ---------------------------------------------------------------------------

  describe "execution_counts/1" do
    test "returns counts grouped by status" do
      scope = build_scope()
      seq = sequence_for(scope)
      c1 = contact_for(scope)
      c2 = contact_for(scope)
      c3 = contact_for(scope)

      {:ok, e1} = Automation.enroll_contact(scope, seq, c1)
      {:ok, e2} = Automation.enroll_contact(scope, seq, c2)
      {:ok, _e3} = Automation.enroll_contact(scope, seq, c3)

      Automation.complete_execution(e1)
      Automation.fail_execution(e2, "error")

      counts = Automation.execution_counts(seq)

      assert counts[:completed] == 1
      assert counts[:failed] == 1
      assert counts[:pending] == 1
    end
  end
end
