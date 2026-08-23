defmodule Konevo.Workers.NoReplyFollowUpWorkerTest do
  use Konevo.DataCase, async: false

  import Konevo.Factory

  alias Konevo.Accounts.Scope
  alias Konevo.Compliance
  alias Konevo.Messaging
  alias Konevo.Workers.NoReplyFollowUpWorker

  test "processes active automatic no-reply workflows" do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: :owner)
    scope = Scope.for_user_in_org(user, org, membership)

    contact =
      insert(:contact,
        organization: org,
        user: user,
        email: "scheduled-follow-up@example.com"
      )

    Compliance.record_consent(contact, :email, :manual)

    thread =
      insert(:email_thread,
        organization: org,
        contact: contact,
        last_inbound_at: DateTime.add(DateTime.utc_now(:second), -5, :day),
        last_outbound_at: DateTime.add(DateTime.utc_now(:second), -4, :day)
      )

    insert(:email,
      organization: org,
      thread: thread,
      from: "lead@example.com",
      is_inbound: true
    )

    sequence =
      insert(:automation_sequence,
        organization: org,
        created_by: user,
        status: :active,
        trigger_type: :inbound_email_idle,
        trigger_config: %{
          "workflow_type" => "no_reply_follow_up",
          "mode" => "automatic",
          "idle_days" => 3,
          "excluded_senders" => []
        }
      )

    insert(:automation_rule,
      organization: org,
      sequence: sequence,
      action_type: :prepare_follow_up,
      action_config: %{"subject" => "Checking in", "body" => "Still interested?"}
    )

    assert :ok = NoReplyFollowUpWorker.perform(%Oban.Job{args: %{"organization_id" => org.id}})

    {sent_messages, 1} = Messaging.list_sent(scope, contact_id: contact.id)
    assert hd(sent_messages).is_automation
  end

  test "returns an error when the workflow owner no longer has a scope" do
    user = insert(:user)
    org = insert(:organization)

    insert(:membership,
      user: user,
      organization: org,
      role: :owner,
      archived_at: DateTime.utc_now(:second)
    )

    insert(:automation_sequence,
      organization: org,
      created_by: user,
      status: :active,
      trigger_type: :inbound_email_idle,
      trigger_config: %{"workflow_type" => "no_reply_follow_up", "mode" => "manual"}
    )

    assert {:error, :missing_scope} = NoReplyFollowUpWorker.perform(%Oban.Job{})
  end
end
