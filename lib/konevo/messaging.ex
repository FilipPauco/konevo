defmodule Konevo.Messaging do
  @moduledoc """
  The Messaging context — outbound messages (email + SMS) and AI draft approvals.

  Flow:
    1. AI (or user) calls `create_draft/3` → stored as `pending`
    2. User reviews, edits, calls `approve_draft/3` → status becomes `approved`
    3. Caller sends via Gmail/Twilio, then calls `record_sent/3` → stored in `messages_sent`
    4. Draft status updated to `sent` via `mark_draft_sent/3`

  Rejection: user calls `reject_draft/2` → status becomes `rejected`, nothing sent.
  """

  import Ecto.Query, warn: false

  alias Konevo.Compliance
  alias Konevo.Contacts
  alias Konevo.Inbox
  alias Konevo.Messaging.{MessageDraft, MessageSent, Policy}
  alias Konevo.Repo

  @per_page 25

  # ---------------------------------------------------------------------------
  # Message Drafts
  # ---------------------------------------------------------------------------

  @doc """
  Returns paginated drafts for the scope's org.

  Options:
    - `:status`         – atom to filter by (`:pending`, `:approved`, `:rejected`, `:sent`)
    - `:ai_generated`   – boolean
    - `:contact_id`     – filter by contact
    - `:thread_id`      – filter by email thread
    - `:page` / `:per_page`
  """
  def list_drafts(scope, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, @per_page)

    filtered =
      scope
      |> draft_base_query()
      |> filter_draft_status(Keyword.get(opts, :status))
      |> filter_draft_ai(Keyword.get(opts, :ai_generated))
      |> filter_draft_contact(Keyword.get(opts, :contact_id))
      |> filter_draft_thread(Keyword.get(opts, :thread_id))

    total = Repo.aggregate(filtered, :count, :id)

    drafts =
      filtered
      |> order_by(desc: :inserted_at)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> preload([:contact, :source_email, :created_by, :approved_by, email_thread: [:emails]])
      |> Repo.all()

    {drafts, total}
  end

  @doc """
  Gets a single draft scoped to org.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_draft!(scope, id) do
    MessageDraft
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> preload([:contact, :email_thread, :created_by, :approved_by, :sent_message])
    |> Repo.one!()
  end

  @doc """
  Creates a draft. `attrs` should include `:message_type`, `:body`, and optionally
  `:subject`, `:tone_preset`, `:ai_generated`, `:ai_model_used`, `:ai_confidence`.
  """
  def create_draft(scope, attrs \\ %{}) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      %MessageDraft{
        organization_id: scope.org.id,
        created_by_id: scope.user.id
      }
      |> MessageDraft.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc false
  def create_automation_draft(scope, attrs, source_email_id)
      when is_integer(source_email_id) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      %MessageDraft{
        organization_id: scope.org.id,
        created_by_id: scope.user.id,
        source_email_id: source_email_id
      }
      |> MessageDraft.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates a pending draft (e.g., user edits before approving).
  Only allowed while status is `:pending`.
  """
  def update_draft(scope, %MessageDraft{status: :pending} = draft, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      draft
      |> MessageDraft.changeset(attrs)
      |> Repo.update()
    end
  end

  def update_draft(_scope, %MessageDraft{}, _attrs), do: {:error, :not_pending}

  @doc """
  Approves a draft. Optionally accepts an edited body — records the change if different.
  Sets `approved_by_id` and `approved_at`.
  """
  def approve_draft(scope, draft, edited_body \\ nil)

  def approve_draft(scope, %MessageDraft{status: :pending} = draft, edited_body) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      draft
      |> MessageDraft.approve_changeset(scope.user.id, edited_body)
      |> Repo.update()
    end
  end

  def approve_draft(_scope, %MessageDraft{}, _edited_body), do: {:error, :not_pending}

  @doc """
  Returns an approved draft to the review queue before it has been sent.
  """
  def unapprove_draft(scope, %MessageDraft{status: :approved} = draft) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      draft
      |> MessageDraft.unapprove_changeset()
      |> Repo.update()
    end
  end

  def unapprove_draft(_scope, %MessageDraft{}), do: {:error, :not_approved}

  @doc """
  Creates or reuses the inbound sender's contact, links it to the source thread,
  and returns an approved draft to review.
  """
  def create_contact_and_unapprove_draft(scope, %MessageDraft{status: :approved} = draft) do
    draft = Repo.preload(draft, email_thread: [:emails])

    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}),
         %{emails: emails} = thread <- draft.email_thread,
         {:ok, sender_email} <- inbound_sender_email(emails) do
      Repo.transact(fn ->
        with {:ok, contact} <- Contacts.find_or_create_by_email(scope, sender_email),
             {:ok, _thread} <- Inbox.link_contact(scope, thread, contact.id),
             {:ok, review_draft} <-
               draft
               |> MessageDraft.link_contact_and_unapprove_changeset(contact.id)
               |> Repo.update() do
          {:ok, %{contact: contact, draft: review_draft}}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      nil -> {:error, :missing_thread}
      error -> error
    end
  end

  def create_contact_and_unapprove_draft(_scope, %MessageDraft{}), do: {:error, :not_approved}

  @doc """
  Checks whether an approved draft may be sent to its contact.
  """
  def draft_sendability(scope, %MessageDraft{} = draft, opts \\ []) do
    draft = Repo.preload(draft, :contact)

    cond do
      draft.organization_id != scope.org.id ->
        {:error, :not_found}

      is_nil(draft.contact) ->
        {:error, :no_contact}

      true ->
        if Keyword.get(opts, :require_consent?, true) do
          Compliance.check_sendable(scope.org, draft.contact, draft.message_type)
        else
          Compliance.check_deliverable(scope.org, draft.contact, draft.message_type)
        end
    end
  end

  @doc """
  Sends an approved draft after compliance checks, then records the delivery.
  """
  def send_approved_draft(scope, draft, opts \\ [])

  def send_approved_draft(scope, %MessageDraft{status: :approved} = draft, opts) do
    draft = Repo.preload(draft, :contact)

    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}),
         :ok <- draft_sendability(scope, draft, opts),
         :ok <- deliver_draft(scope, draft),
         {:ok, sent} <- record_sent(scope, sent_attrs_from_draft(draft)) do
      {:ok, updated} = mark_draft_sent(scope, draft, sent)
      {:ok, updated}
    end
  end

  def send_approved_draft(_scope, %MessageDraft{}, _opts), do: {:error, :not_approved}

  @doc """
  Rejects a draft. Sets status to `:rejected` — nothing will be sent.
  """
  def reject_draft(scope, %MessageDraft{status: :pending} = draft) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      draft
      |> MessageDraft.reject_changeset()
      |> Repo.update()
    end
  end

  def reject_draft(_scope, %MessageDraft{}), do: {:error, :not_pending}

  @doc """
  Rejects all pending or approved drafts in the current organization's review queue.
  """
  def reject_all_review_drafts(scope) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      {count, _} =
        scope
        |> draft_base_query()
        |> where([draft], draft.status in [:pending, :approved])
        |> Repo.update_all(set: [status: :rejected, updated_at: DateTime.utc_now(:second)])

      {:ok, count}
    end
  end

  @doc """
  Returns a changeset for tracking draft changes.
  """
  def change_draft(%MessageDraft{} = draft, attrs \\ %{}) do
    MessageDraft.changeset(draft, attrs)
  end

  # ---------------------------------------------------------------------------
  # Messages Sent
  # ---------------------------------------------------------------------------

  @doc """
  Returns paginated sent messages for the scope's org.

  Options:
    - `:message_type`  – `:email` | `:sms`
    - `:status`        – atom to filter by
    - `:contact_id`    – filter by contact
    - `:page` / `:per_page`
  """
  def list_sent(scope, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, @per_page)

    filtered =
      scope
      |> sent_base_query()
      |> filter_sent_type(Keyword.get(opts, :message_type))
      |> filter_sent_status(Keyword.get(opts, :status))
      |> filter_sent_contact(Keyword.get(opts, :contact_id))

    total = Repo.aggregate(filtered, :count, :id)

    messages =
      filtered
      |> order_by(desc: :sent_at)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> preload([:contact, :sent_by])
      |> Repo.all()

    {messages, total}
  end

  @doc """
  Gets a single sent message scoped to org.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_sent!(scope, id) do
    MessageSent
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> preload([:contact, :sent_by])
    |> Repo.one!()
  end

  @doc """
  Records a message as sent. Called after the external send (Gmail/Twilio) succeeds.
  Links to the draft if `draft_id` provided in attrs.
  """
  def record_sent(scope, attrs \\ %{}) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      %MessageSent{
        organization_id: scope.org.id,
        sent_by_id: scope.user.id
      }
      |> MessageSent.changeset(Map.put(attrs, :sent_at, DateTime.utc_now(:second)))
      |> Repo.insert()
    end
  end

  @doc """
  Marks a draft as sent and links it to the `MessageSent` record.
  Called after `record_sent/2` succeeds.
  """
  def mark_draft_sent(scope, %MessageDraft{status: :approved} = draft, %MessageSent{} = sent) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      draft
      |> Ecto.Changeset.change(status: :sent, sent_message_id: sent.id)
      |> Repo.update()
    end
  end

  def mark_draft_sent(_scope, %MessageDraft{}, _sent), do: {:error, :not_approved}

  @doc """
  Updates delivery status on a sent message (e.g., from webhook: opened, bounced).
  """
  def update_delivery_status(%MessageSent{} = message, status, extra \\ %{}) do
    changes = Map.merge(%{status: status, delivery_status: to_string(status)}, extra)

    message
    |> Ecto.Changeset.cast(changes, [:status, :delivery_status, :opened_at, :clicked_at])
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Stats
  # ---------------------------------------------------------------------------

  @doc """
  Returns count of pending AI-generated drafts awaiting approval.
  """
  def pending_draft_count(scope) do
    MessageDraft
    |> where(organization_id: ^scope.org.id, status: :pending, ai_generated: true)
    |> Repo.aggregate(:count, :id)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp draft_base_query(%{org: %{id: org_id}}) do
    from(d in MessageDraft, where: d.organization_id == ^org_id)
  end

  defp inbound_sender_email(emails) when is_list(emails) do
    emails
    |> Enum.filter(& &1.is_inbound)
    |> Enum.max_by(& &1.received_at, DateTime, fn -> nil end)
    |> case do
      %{from: from} when is_binary(from) and from != "" -> {:ok, from}
      _ -> {:error, :missing_sender}
    end
  end

  defp inbound_sender_email(_emails), do: {:error, :missing_sender}

  defp filter_draft_status(query, nil), do: query

  defp filter_draft_status(query, statuses) when is_list(statuses),
    do: from(d in query, where: d.status in ^statuses)

  defp filter_draft_status(query, s), do: from(d in query, where: d.status == ^s)

  defp filter_draft_ai(query, nil), do: query
  defp filter_draft_ai(query, val), do: from(d in query, where: d.ai_generated == ^val)

  defp filter_draft_contact(query, nil), do: query
  defp filter_draft_contact(query, id), do: from(d in query, where: d.contact_id == ^id)

  defp filter_draft_thread(query, nil), do: query
  defp filter_draft_thread(query, id), do: from(d in query, where: d.email_thread_id == ^id)

  defp sent_attrs_from_draft(%MessageDraft{} = draft) do
    %{
      message_type: draft.message_type,
      recipient: draft_recipient(draft),
      subject: draft.subject,
      body: draft.body,
      status: :sent,
      contact_id: draft.contact_id,
      is_manual: false,
      is_automation: draft.ai_generated
    }
  end

  defp draft_recipient(%MessageDraft{message_type: :email, contact: %{email: email}}), do: email
  defp draft_recipient(%MessageDraft{message_type: :sms, contact: %{phone: phone}}), do: phone
  defp draft_recipient(_draft), do: ""

  defp deliver_draft(
         scope,
         %MessageDraft{message_type: :email, email_thread_id: thread_id} = draft
       )
       when is_integer(thread_id) do
    case Inbox.send_reply(scope, thread_id, draft.body) do
      {:ok, _email} -> :ok
      {:error, :no_integration} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver_draft(_scope, _draft), do: :ok

  defp sent_base_query(%{org: %{id: org_id}}) do
    from(m in MessageSent, where: m.organization_id == ^org_id)
  end

  defp filter_sent_type(query, nil), do: query
  defp filter_sent_type(query, t), do: from(m in query, where: m.message_type == ^t)

  defp filter_sent_status(query, nil), do: query
  defp filter_sent_status(query, s), do: from(m in query, where: m.status == ^s)

  defp filter_sent_contact(query, nil), do: query
  defp filter_sent_contact(query, id), do: from(m in query, where: m.contact_id == ^id)
end
