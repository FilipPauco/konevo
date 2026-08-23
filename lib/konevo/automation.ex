defmodule Konevo.Automation do
  @moduledoc """
  The Automation context — sequences, rules (steps), and executions.

  ## Concepts

  **Sequence** — a named workflow triggered by an event (contact created, deal
  stage changed, etc.) or run manually. Contains an ordered list of rules.

  **Rule** — a single step in a sequence: send an email, wait N days, create a
  task, update a contact's status, etc. Configured via `action_config` (JSONB).

  **Execution** — a contact going through a sequence. One execution per
  (sequence, contact) while active — duplicate enrollments are blocked at the
  DB level. Workers advance executions step-by-step; results (emails sent,
  tasks created) are recorded in the relevant contexts.
  """

  import Ecto.Query, warn: false

  alias Konevo.Accounts.Organization
  alias Konevo.AI
  alias Konevo.Automation.{Execution, Policy, Rule, Sequence, TaskApproval}
  alias Konevo.Contacts.Contact
  alias Konevo.Inbox.{Email, EmailThread}
  alias Konevo.Messaging
  alias Konevo.Messaging.MessageDraft
  alias Konevo.Repo
  alias Konevo.Tasks

  # ---------------------------------------------------------------------------
  # Sequences — CRUD
  # ---------------------------------------------------------------------------

  @doc """
  Returns all sequences for the scope's org, newest first.
  Accepts `status:` filter option.
  """
  def list_sequences(scope, opts \\ []) do
    status = Keyword.get(opts, :status)

    Sequence
    |> where(organization_id: ^scope.org.id)
    |> maybe_filter_status(status)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns task approvals waiting in the automation review queue.
  """
  def list_task_approvals(scope, opts \\ []) do
    status = Keyword.get(opts, :status)
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    filtered =
      TaskApproval
      |> where(organization_id: ^scope.org.id)
      |> maybe_filter_status(status)

    total = Repo.aggregate(filtered, :count, :id)

    approvals =
      filtered
      |> order_by(desc: :inserted_at)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> preload([:email, :email_thread, :contact, :company, :sequence, :created_task])
      |> Repo.all()

    {approvals, total}
  end

  def get_task_approval!(scope, id) do
    TaskApproval
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> preload([:email, :email_thread, :contact, :company, :sequence, :created_task])
    |> Repo.one!()
  end

  def approve_task_approval(scope, %TaskApproval{status: :pending} = approval, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      Repo.transaction(fn -> approve_task_approval_transaction(scope, approval, attrs) end)
    end
  end

  def approve_task_approval(_scope, %TaskApproval{}, _attrs), do: {:error, :not_pending}

  defp approve_task_approval_transaction(scope, approval, attrs) do
    attrs = approval_task_attrs(approval, attrs)

    case Tasks.create_task(scope, attrs) do
      {:ok, task} ->
        approval
        |> TaskApproval.approve_changeset(scope.user.id, task.id, attrs)
        |> Repo.update!()

        task

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  def reject_task_approval(scope, %TaskApproval{status: :pending} = approval) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      approval
      |> TaskApproval.reject_changeset()
      |> Repo.update()
    end
  end

  def reject_task_approval(_scope, %TaskApproval{}), do: {:error, :not_pending}

  def change_approval_expiry(scope, attrs \\ %{}) do
    Organization.approval_expiry_changeset(scope.org, attrs)
  end

  def update_approval_expiry(scope, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      scope.org
      |> Organization.approval_expiry_changeset(attrs)
      |> Repo.update()
    end
  end

  def expire_pending_approvals(now \\ DateTime.utc_now(:second)) do
    Organization
    |> Repo.all()
    |> Enum.reduce(%{drafts: 0, tasks: 0}, fn organization, totals ->
      expire_organization_approvals(organization, now, totals)
    end)
    |> then(&{:ok, &1})
  end

  @doc """
  Gets a single sequence scoped to the org. Raises if not found.
  """
  def get_sequence!(scope, id) do
    Sequence
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> Repo.one!()
  end

  @doc """
  Gets a sequence with ordered rules, scoped to the org.
  """
  def get_sequence_with_rules!(scope, id) do
    scope
    |> get_sequence!(id)
    |> Repo.preload(rules: from(r in Rule, order_by: [asc: r.position]))
  end

  @doc """
  Returns a changeset for sequence forms.
  """
  def change_sequence(%Sequence{} = sequence, attrs \\ %{}) do
    Sequence.changeset(sequence, attrs)
  end

  @doc """
  Creates a new sequence in draft status.
  """
  def create_sequence(scope, attrs \\ %{}) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      %Sequence{organization_id: scope.org.id, created_by_id: scope.user.id}
      |> Sequence.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates a sequence's name, description, trigger, or config.
  """
  def update_sequence(scope, %Sequence{} = sequence, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      sequence
      |> Sequence.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Activates a draft or paused sequence.
  """
  def activate_sequence(scope, %Sequence{} = sequence) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}),
         false <- active_workflow_type_exists?(scope, sequence) do
      sequence
      |> Ecto.Changeset.change(status: :active, activated_at: DateTime.utc_now(:second))
      |> Repo.update()
    else
      true -> {:error, :workflow_type_already_active}
      error -> error
    end
  end

  @doc """
  Pauses an active sequence. In-flight executions continue; no new enrollments.
  """
  def pause_sequence(scope, %Sequence{} = sequence) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      sequence
      |> Ecto.Changeset.change(status: :paused)
      |> Repo.update()
    end
  end

  @doc """
  Archives a sequence. Cannot be re-activated.
  """
  def archive_sequence(scope, %Sequence{} = sequence) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      sequence
      |> Ecto.Changeset.change(status: :archived)
      |> Repo.update()
    end
  end

  defp active_workflow_type_exists?(scope, sequence) do
    case get_in(sequence.trigger_config || %{}, ["workflow_type"]) do
      workflow_type when is_binary(workflow_type) ->
        Repo.exists?(
          from candidate in Sequence,
            where:
              candidate.organization_id == ^scope.org.id and candidate.status == :active and
                candidate.id != ^sequence.id and
                fragment("?->>'workflow_type' = ?", candidate.trigger_config, ^workflow_type)
        )

      _ ->
        false
    end
  end

  @doc """
  Deletes a sequence and all its rules and executions (cascade).
  Only allowed for draft or archived sequences.
  """
  def delete_sequence(scope, %Sequence{status: status} = sequence)
      when status in [:draft, :archived] do
    with :ok <- Bodyguard.permit(Policy, :delete, scope.user, %{org: scope.org}) do
      Repo.delete(sequence)
    end
  end

  def delete_sequence(_scope, %Sequence{}), do: {:error, :cannot_delete_active_sequence}

  # ---------------------------------------------------------------------------
  # Rules (steps)
  # ---------------------------------------------------------------------------

  @doc """
  Returns all rules for a sequence, ordered by position.
  """
  def list_rules(%Sequence{} = sequence) do
    Rule
    |> where(sequence_id: ^sequence.id)
    |> order_by(asc: :position)
    |> Repo.all()
  end

  @doc """
  Returns a changeset for rule forms.
  """
  def change_rule(%Rule{} = rule, attrs \\ %{}) do
    Rule.changeset(rule, attrs)
  end

  @doc """
  Adds a step to a sequence. Position defaults to next available slot.
  """
  def add_rule(scope, %Sequence{} = sequence, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      next_position = next_rule_position(sequence)

      %Rule{
        organization_id: scope.org.id,
        sequence_id: sequence.id
      }
      |> Rule.changeset(put_default_position(attrs, next_position))
      |> Repo.insert()
    end
  end

  @doc """
  Updates a rule's action_type, action_config, delay_seconds, or position.
  """
  def update_rule(scope, %Rule{} = rule, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      rule
      |> Rule.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes a rule from a sequence.
  """
  def delete_rule(scope, %Rule{} = rule) do
    with :ok <- Bodyguard.permit(Policy, :delete, scope.user, %{org: scope.org}) do
      Repo.delete(rule)
    end
  end

  # ---------------------------------------------------------------------------
  # Executions
  # ---------------------------------------------------------------------------

  @doc """
  Enrolls a contact into a sequence. Idempotent — returns existing active
  execution if one already exists for this (sequence, contact) pair.
  """
  def enroll_contact(scope, %Sequence{} = sequence, %Contact{} = contact) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      case active_execution_for(sequence, contact) do
        %Execution{} = existing ->
          {:ok, existing}

        nil ->
          %Execution{
            organization_id: scope.org.id,
            sequence_id: sequence.id,
            contact_id: contact.id
          }
          |> Execution.changeset(%{status: :pending, enrolled_at: DateTime.utc_now(:second)})
          |> Repo.insert()
      end
    end
  end

  @doc """
  Advances an execution to the given next rule. Sets status to :running.
  Called by Oban workers as they process each step.
  """
  def advance_execution(%Execution{} = execution, %Rule{} = next_rule) do
    execution
    |> Execution.advance_changeset(next_rule)
    |> Repo.update()
  end

  @doc """
  Marks an execution as completed (all steps done).
  """
  def complete_execution(%Execution{} = execution) do
    execution
    |> Execution.complete_changeset()
    |> Repo.update()
  end

  @doc """
  Marks an execution as failed with a reason.
  """
  def fail_execution(%Execution{} = execution, reason) do
    execution
    |> Execution.fail_changeset(reason)
    |> Repo.update()
  end

  @doc """
  Cancels a pending or running execution.
  """
  def cancel_execution(%Execution{} = execution) do
    execution
    |> Execution.cancel_changeset()
    |> Repo.update()
  end

  @doc """
  Cancels all active executions for a contact after an inbound reply.
  """
  def cancel_active_executions_for_contact(scope, %Contact{} = contact) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      cancel_active_executions_for_contact_id(scope.org.id, contact.id)
    end
  end

  @doc """
  System-level inbound reply stop. Used by inbox import paths where no actor exists.
  """
  def cancel_active_executions_for_contact_id(_org_id, nil), do: {:ok, 0}

  def cancel_active_executions_for_contact_id(org_id, contact_id) do
    now = DateTime.utc_now(:second)

    {count, _} =
      Execution
      |> where(
        [e],
        e.organization_id == ^org_id and e.contact_id == ^contact_id and
          e.status in [:pending, :running]
      )
      |> Repo.update_all(
        set: [
          status: :cancelled,
          completed_at: now,
          error_message: "Stopped after inbound reply",
          updated_at: now
        ]
      )

    {:ok, count}
  end

  @doc """
  Finds threads where the latest outbound reply is older than N days and the
  customer has not replied since. By default it creates pending approval drafts;
  passing `mode: "automatic"` approves and sends the draft after compliance checks.
  """
  def prepare_stale_inbound_follow_ups(scope, days, attrs \\ %{}) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}),
         {:ok, days} <- normalize_days(days) do
      scope
      |> unanswered_outbound_threads(days)
      |> Enum.map(&create_follow_up(scope, &1, attrs))
      |> split_results()
    end
  end

  @doc """
  Runs every active no-reply follow-up workflow for the scope's organization.

  Each workflow controls its own delay, excluded senders, subject, body, and
  approval mode. Automatic sends remain subject to the normal consent and
  suppression checks in `Konevo.Messaging`.
  """
  def prepare_active_no_reply_follow_ups(scope) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      scope
      |> active_no_reply_follow_up_sequences()
      |> Enum.map(&run_no_reply_follow_up_sequence(scope, &1))
      |> split_workflow_results()
    end
  end

  @doc """
  Runs active inbound-email task workflows for a newly imported inbound email.
  """
  def prepare_inbound_email_tasks(scope, %Email{is_inbound: true} = email) do
    email = Repo.preload(email, thread: [:contact])

    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}),
         false <- source_email_work_exists?(scope, email.id) do
      scope
      |> active_inbound_email_task_sequences()
      |> Enum.map(&run_inbound_email_task_sequence(scope, email, &1))
      |> split_workflow_results()
    else
      true -> {:ok, [], []}
      error -> error
    end
  end

  def prepare_inbound_email_tasks(_scope, %Email{}), do: {:ok, [], []}

  @doc """
  Runs active AI-reply workflows for a newly imported inbound email.
  """
  def prepare_inbound_email_replies(scope, %Email{is_inbound: true} = email) do
    email = Repo.preload(email, thread: [:contact])

    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}),
         false <- source_email_reply_exists?(scope, email.id) do
      scope
      |> active_inbound_email_reply_sequences()
      |> Enum.filter(&email_received_after_activation?(&1, email))
      |> Enum.reject(
        &excluded_email_sender?(email, Map.get(&1.trigger_config || %{}, "excluded_senders", []))
      )
      |> Enum.map(&run_inbound_email_reply_sequence(scope, email, &1))
      |> split_workflow_results()
    else
      true -> {:ok, [], []}
      error -> error
    end
  end

  def prepare_inbound_email_replies(_scope, %Email{}), do: {:ok, [], []}

  @doc """
  Returns the active (pending or running) execution for a contact in a sequence,
  or nil if none exists.
  """
  def active_execution_for(%Sequence{} = sequence, %Contact{} = contact) do
    Execution
    |> where(sequence_id: ^sequence.id, contact_id: ^contact.id)
    |> where([e], e.status in [:pending, :running])
    |> Repo.one()
  end

  @doc """
  Returns all executions for a sequence, newest first.
  Accepts `status:` filter option.
  """
  def list_executions(scope, %Sequence{} = sequence, opts \\ []) do
    status = Keyword.get(opts, :status)

    Execution
    |> where(organization_id: ^scope.org.id, sequence_id: ^sequence.id)
    |> maybe_filter_status(status)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns execution counts grouped by status for a sequence.
  Useful for dashboards showing how many contacts are at each stage.
  """
  def execution_counts(%Sequence{} = sequence) do
    Execution
    |> where(sequence_id: ^sequence.id)
    |> group_by([e], e.status)
    |> select([e], {e.status, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, statuses) when is_list(statuses),
    do: where(query, [a], a.status in ^statuses)

  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp put_default_position(attrs, position) do
    cond do
      Map.has_key?(attrs, :position) or Map.has_key?(attrs, "position") -> attrs
      string_keyed?(attrs) -> Map.put(attrs, "position", position)
      true -> Map.put(attrs, :position, position)
    end
  end

  defp string_keyed?(attrs) do
    Enum.any?(attrs, fn {key, _value} -> is_binary(key) end)
  end

  defp normalize_days(days) when is_integer(days) and days >= 1, do: {:ok, days}
  defp normalize_days(0), do: {:ok, 1}

  defp normalize_days(days) when is_binary(days) do
    case Integer.parse(days) do
      {value, ""} when value >= 1 -> {:ok, value}
      {0, ""} -> {:ok, 1}
      _ -> {:error, :invalid_days}
    end
  end

  defp normalize_days(_days), do: {:error, :invalid_days}

  defp follow_up_delay_seconds(days), do: days * 86_400

  defp unanswered_outbound_threads(scope, days) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -follow_up_delay_seconds(days), :second)

    EmailThread
    |> join(:inner, [t], c in assoc(t, :contact))
    |> join(:left, [t], d in MessageDraft,
      on:
        d.email_thread_id == t.id and d.status != :rejected and
          d.inserted_at >= t.last_outbound_at
    )
    |> where([t, _c, d], t.organization_id == ^scope.org.id and is_nil(d.id))
    |> where([t], not is_nil(t.last_outbound_at) and t.last_outbound_at <= ^cutoff)
    |> where([t], is_nil(t.last_inbound_at) or t.last_inbound_at < t.last_outbound_at)
    |> order_by([t], asc: t.last_outbound_at)
    |> limit(50)
    |> preload([_t, c, _d], contact: c, emails: [])
    |> Repo.all()
  end

  defp create_follow_up(scope, thread, attrs) do
    if follow_up_mode(attrs) == "automatic" do
      create_and_send_follow_up(scope, thread, attrs)
    else
      create_follow_up_draft(scope, thread, attrs)
    end
  end

  defp create_follow_up_draft(scope, thread, attrs) do
    contact = thread.contact

    attrs =
      %{
        message_type: :email,
        subject: Map.get(attrs, "subject", Map.get(attrs, :subject, "Follow-up")),
        body: follow_up_body(contact, attrs),
        ai_generated: true,
        tone_preset: :professional,
        contact_id: contact.id,
        email_thread_id: thread.id
      }

    Messaging.create_draft(scope, attrs)
  end

  defp create_and_send_follow_up(scope, thread, attrs) do
    case Repo.transaction(fn -> send_follow_up(scope, thread, attrs) end) do
      {:ok, draft} -> {:ok, draft}
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_follow_up(scope, thread, attrs) do
    with {:ok, draft} <- create_follow_up_draft(scope, thread, attrs),
         {:ok, approved} <- Messaging.approve_draft(scope, draft),
         {:ok, sent} <- Messaging.send_approved_draft(scope, approved, require_consent?: false) do
      sent
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp active_no_reply_follow_up_sequences(scope) do
    Sequence
    |> where(
      organization_id: ^scope.org.id,
      status: :active,
      trigger_type: :inbound_email_idle
    )
    |> where([s], fragment("?->>'workflow_type' = ?", s.trigger_config, "no_reply_follow_up"))
    |> preload(rules: ^from(r in Rule, order_by: [asc: r.position]))
    |> Repo.all()
  end

  defp run_no_reply_follow_up_sequence(scope, %Sequence{} = sequence) do
    config = sequence.trigger_config || %{}
    rule = Enum.find(sequence.rules, &(&1.action_type == :prepare_follow_up))
    attrs = Map.merge(config, if(rule, do: rule.action_config || %{}, else: %{}))

    with {:ok, days} <- normalize_days(Map.get(config, "idle_days")) do
      results =
        scope
        |> unanswered_outbound_threads(days)
        |> Enum.reject(&excluded_sender?(&1, Map.get(config, "excluded_senders", [])))
        |> Enum.map(&create_follow_up(scope, &1, attrs))

      case split_results(results) do
        {:ok, drafts, []} -> {:ok, drafts}
        {:ok, _drafts, errors} -> {:error, errors}
      end
    end
  end

  defp excluded_sender?(thread, exclusions) do
    sender =
      thread.emails
      |> Enum.filter(& &1.is_inbound)
      |> Enum.max_by(& &1.received_at, fn -> nil end)
      |> case do
        nil -> nil
        email -> email.from
      end

    sender && Enum.any?(normalize_excluded_senders(exclusions), &sender_matches?(&1, sender))
  end

  defp excluded_email_sender?(%Email{from: sender}, exclusions) do
    sender && Enum.any?(normalize_excluded_senders(exclusions), &sender_matches?(&1, sender))
  end

  defp normalize_excluded_senders(exclusions) when is_list(exclusions), do: exclusions

  defp normalize_excluded_senders(exclusions) when is_binary(exclusions) do
    String.split(exclusions, ~r/[\n,]+/, trim: true)
  end

  defp normalize_excluded_senders(_exclusions), do: []

  defp sender_matches?(pattern, sender) do
    expression =
      pattern
      |> String.downcase()
      |> Regex.escape()
      |> String.replace("\\*", ".*")

    String.match?(String.downcase(sender), Regex.compile!("^#{expression}$"))
  end

  defp active_inbound_email_task_sequences(scope) do
    Sequence
    |> where(
      organization_id: ^scope.org.id,
      status: :active,
      trigger_type: :inbound_email_received
    )
    |> where([s], fragment("?->>'workflow_type' = ?", s.trigger_config, "inbound_email_task"))
    |> preload(rules: ^from(r in Rule, order_by: [asc: r.position]))
    |> Repo.all()
  end

  defp active_inbound_email_reply_sequences(scope) do
    Sequence
    |> where(
      organization_id: ^scope.org.id,
      status: :active,
      trigger_type: :inbound_email_received
    )
    |> where([s], fragment("?->>'workflow_type' = ?", s.trigger_config, "inbound_email_reply"))
    |> preload(rules: ^from(r in Rule, order_by: [asc: r.position]))
    |> Repo.all()
  end

  defp run_inbound_email_reply_sequence(scope, %Email{} = email, %Sequence{} = sequence) do
    rule = Enum.find(sequence.rules, &(&1.action_type == :prepare_reply))

    config =
      Map.merge(
        sequence.trigger_config || %{},
        if(rule, do: rule.action_config || %{}, else: %{})
      )

    with {:ok, %{content: body}} <- AI.generate_reply_draft(scope, email.thread, config) do
      create_ai_reply(scope, email, body)
    end
  end

  defp create_ai_reply(scope, email, body) do
    attrs = %{
      message_type: :email,
      subject: reply_subject(email.thread.subject),
      body: reply_draft_text(body),
      ai_generated: true,
      tone_preset: :professional,
      contact_id: email.thread.contact_id,
      email_thread_id: email.thread_id
    }

    with {:ok, draft} <- Messaging.create_automation_draft(scope, attrs, email.id) do
      broadcast_approval_queue_changed(scope.org.id)
      {:ok, draft}
    end
  end

  defp source_email_reply_exists?(scope, email_id) do
    Repo.exists?(
      from draft in MessageDraft,
        where: draft.organization_id == ^scope.org.id and draft.source_email_id == ^email_id
    )
  end

  defp email_received_after_activation?(
         %Sequence{activated_at: %DateTime{} = activated_at},
         %Email{
           received_at: %DateTime{} = received_at
         }
       ) do
    DateTime.compare(received_at, activated_at) in [:eq, :gt]
  end

  defp email_received_after_activation?(_sequence, _email), do: false

  defp reply_draft_text(body) do
    body
    |> to_string()
    |> decode_reply_entities()
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<\/(?:p|div|li|h[1-6])\s*>/i, "\n\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp decode_reply_entities(text) do
    text
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&#x27;", "'")
  end

  defp broadcast_approval_queue_changed(org_id) do
    Phoenix.PubSub.broadcast(
      Konevo.PubSub,
      "automation:approvals:#{org_id}",
      :automation_approvals_changed
    )
  end

  defp reply_subject(nil), do: "Re: (no subject)"
  defp reply_subject(subject), do: "Re: " <> subject

  defp run_inbound_email_task_sequence(scope, %Email{} = email, %Sequence{} = sequence) do
    rule = Enum.find(sequence.rules, &(&1.action_type == :prepare_task))
    config = if rule, do: rule.action_config || %{}, else: %{}

    with {:ok, result} <- AI.extract_tasks_from_email(scope, email, config) do
      create_email_tasks(scope, email, sequence, config, result)
    end
  end

  defp create_email_tasks(scope, email, sequence, _config, %{tasks: tasks, extraction: extraction}) do
    mode = sequence_mode(sequence)

    case mode do
      "automatic" -> create_extracted_tasks(scope, email, tasks, extraction)
      _ -> create_task_approvals(scope, email, sequence, tasks)
    end
  end

  defp create_extracted_tasks(_scope, _email, [], _extraction), do: {:ok, []}

  defp create_extracted_tasks(scope, email, tasks, extraction) do
    tasks
    |> Enum.map(&create_task_from_extraction(scope, email, &1, extraction))
    |> split_task_results()
  end

  defp create_task_approvals(_scope, _email, _sequence, []), do: {:ok, []}

  defp create_task_approvals(scope, email, sequence, tasks) do
    tasks
    |> Enum.map(&create_task_approval(scope, email, sequence, &1))
    |> split_task_results()
  end

  defp create_task_approval(scope, email, sequence, task) do
    attrs =
      email
      |> base_approval_attrs()
      |> Map.merge(%{
        sequence_id: sequence.id,
        title: Map.fetch!(task, "title"),
        description: Map.get(task, "description"),
        due_date: task_due_date(task, email),
        priority: task_priority(task),
        confidence: Map.get(task, "confidence")
      })

    %TaskApproval{organization_id: scope.org.id}
    |> TaskApproval.changeset(attrs)
    |> Repo.insert()
  end

  defp create_task_from_extraction(scope, email, task, extraction) do
    attrs =
      email
      |> base_task_attrs()
      |> Map.merge(%{
        title: Map.fetch!(task, "title"),
        description: extracted_task_description(task, extraction),
        due_date: task_due_date(task, email),
        priority: task_priority(task)
      })

    Tasks.create_task(scope, attrs)
  end

  defp base_approval_attrs(%Email{} = email) do
    thread = email.thread
    contact = thread && thread.contact

    %{
      email_id: email.id,
      email_thread_id: email.thread_id,
      contact_id: thread && thread.contact_id,
      company_id: contact && contact.company_id
    }
  end

  defp base_task_attrs(%Email{} = email) do
    thread = email.thread
    contact = thread && thread.contact

    %{
      due_date: default_due_date(email),
      source_email_id: email.id,
      source_thread_id: email.thread_id,
      contact_id: thread && thread.contact_id,
      company_id: contact && contact.company_id
    }
  end

  defp extracted_task_description(task, extraction) do
    [
      Map.get(task, "description"),
      "Created from inbound email by AI extraction.",
      "Confidence: #{format_confidence(Map.get(task, "confidence"))}",
      "Extraction record: #{extraction.id}"
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp task_due_date(task, email) do
    case parse_due_date(Map.get(task, "due_date")) do
      {:ok, due_date} -> due_date
      :error -> default_due_date(email)
    end
  end

  defp parse_due_date(nil), do: :error
  defp parse_due_date(""), do: :error
  defp parse_due_date(%DateTime{} = value), do: {:ok, value}

  defp parse_due_date(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, due_date, _offset} ->
        {:ok, DateTime.shift_zone!(due_date, "Etc/UTC")}

      {:error, _reason} ->
        with {:error, _reason} <- parse_naive_due_date(value),
             {:error, _reason} <- parse_due_date_only(value) do
          :error
        end
    end
  end

  defp parse_due_date(_value), do: :error

  defp parse_naive_due_date(value) do
    with {:error, _reason} <- NaiveDateTime.from_iso8601(value),
         {:error, _reason} <- NaiveDateTime.from_iso8601(value <> ":00") do
      {:error, :invalid_datetime}
    else
      {:ok, due_date} -> {:ok, DateTime.from_naive!(due_date, "Etc/UTC")}
    end
  end

  defp parse_due_date_only(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, DateTime.new!(date, ~T[17:00:00], "Etc/UTC")}
      {:error, reason} -> {:error, reason}
    end
  end

  defp default_due_date(%Email{received_at: %DateTime{} = received_at}) do
    DateTime.add(received_at, 86_400, :second)
  end

  defp default_due_date(_email), do: DateTime.add(DateTime.utc_now(:second), 86_400, :second)

  defp task_priority(%{"priority" => priority})
       when priority in ["low", "normal", "high", "urgent"] do
    String.to_existing_atom(priority)
  end

  defp task_priority(_task), do: :normal

  defp expire_organization_approvals(organization, now, totals) do
    cutoff =
      DateTime.add(now, -approval_expiry_seconds(organization.approval_expiry_days), :second)

    {tasks, _} = expire_task_approvals(organization.id, cutoff, now)
    {drafts, _} = expire_drafts(organization.id, cutoff, now)

    if tasks + drafts > 0, do: broadcast_approval_queue_changed(organization.id)

    %{drafts: totals.drafts + drafts, tasks: totals.tasks + tasks}
  end

  defp approval_expiry_seconds(days), do: days * 86_400

  defp expire_task_approvals(organization_id, cutoff, now) do
    TaskApproval
    |> where([approval], approval.organization_id == ^organization_id)
    |> where([approval], approval.status == :pending and approval.inserted_at <= ^cutoff)
    |> Repo.update_all(set: [status: :rejected, updated_at: now])
  end

  defp expire_drafts(organization_id, cutoff, now) do
    MessageDraft
    |> where([draft], draft.organization_id == ^organization_id)
    |> where([draft], draft.status == :pending and draft.inserted_at <= ^cutoff)
    |> Repo.update_all(set: [status: :rejected, updated_at: now])
  end

  defp source_email_work_exists?(scope, email_id) do
    Tasks.source_email_task_exists?(scope, email_id) or
      Repo.exists?(
        from approval in TaskApproval,
          where:
            approval.organization_id == ^scope.org.id and approval.email_id == ^email_id and
              approval.status in [:pending, :approved]
      )
  end

  defp approval_task_attrs(approval, attrs) do
    due_date =
      case parse_due_date(Map.get(attrs, "due_date", approval.due_date)) do
        {:ok, due_date} -> due_date
        :error -> approval.due_date
      end

    %{
      title: Map.get(attrs, "title", approval.title),
      description: Map.get(attrs, "description", approval.description),
      due_date: due_date,
      priority: Map.get(attrs, "priority", Atom.to_string(approval.priority)),
      source_email_id: approval.email_id,
      source_thread_id: approval.email_thread_id,
      contact_id: approval.contact_id,
      company_id: approval.company_id
    }
  end

  defp sequence_mode(%Sequence{trigger_config: config}) do
    Map.get(config || %{}, "mode") || "manual"
  end

  defp follow_up_mode(attrs) do
    Map.get(attrs, "mode", Map.get(attrs, :mode, "manual"))
  end

  defp split_task_results(results) do
    {ok, errors} =
      Enum.split_with(results, fn
        {:ok, _task} -> true
        _ -> false
      end)

    if errors == [] do
      {:ok, Enum.map(ok, fn {:ok, task} -> task end)}
    else
      {:error, errors}
    end
  end

  defp split_workflow_results(results) do
    {ok, error} =
      Enum.split_with(results, fn
        {:ok, _result} -> true
        _ -> false
      end)

    {:ok, Enum.flat_map(ok, &workflow_result_items/1), error}
  end

  defp workflow_result_items({:ok, results}) when is_list(results), do: results
  defp workflow_result_items({:ok, result}), do: [result]

  defp format_confidence(nil), do: "unknown"
  defp format_confidence(confidence), do: "#{round(confidence * 100)}%"

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp follow_up_body(contact, attrs) do
    body = Map.get(attrs, "body", Map.get(attrs, :body))

    if is_binary(body) and String.trim(body) != "" do
      body
    else
      "Hi #{contact.first_name},\n\nJust checking in on my previous email. Happy to help if you have any questions.\n\nBest,"
    end
  end

  defp split_results(results) do
    {ok, error} =
      Enum.split_with(results, fn
        {:ok, _draft} -> true
        _ -> false
      end)

    {:ok, Enum.map(ok, fn {:ok, draft} -> draft end), error}
  end

  defp next_rule_position(%Sequence{id: seq_id}) do
    case Repo.one(from r in Rule, where: r.sequence_id == ^seq_id, select: max(r.position)) do
      nil -> 0
      max_pos -> max_pos + 1
    end
  end
end
