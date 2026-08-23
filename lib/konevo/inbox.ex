defmodule Konevo.Inbox do
  @moduledoc """
  The Inbox context — email integrations, threads, and individual emails.

  Integrations store OAuth credentials (populated when Gmail/Outlook is wired).
  Threads and emails are the raw inbox data layer consumed by the AI features.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Konevo.Accounts.Scope
  alias Konevo.Automation

  alias Konevo.Inbox.{
    Email,
    EmailBranding,
    EmailIntegration,
    EmailThread,
    GmailClient,
    Policy,
    ScheduledEmail
  }

  alias Konevo.Repo
  alias Konevo.Uploads

  alias Konevo.Workers.{
    GmailBackfillWorker,
    GmailSyncWorker,
    GmailThreadReadStateWorker,
    NoReplyFollowUpWorker
  }

  alias Konevo.Workers.ScheduledEmailWorker

  @doc """
  Creates or updates an email integration after a successful OAuth flow.

  If an integration for the same org + email already exists, its tokens are updated.
  Otherwise a new integration record is inserted.

  `token_attrs` must include `:access_token`, `:refresh_token`, `:token_expires_at`.
  """
  def connect_gmail(scope, email, token_attrs) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      case Repo.get_by(EmailIntegration,
             organization_id: scope.org.id,
             provider: :gmail,
             email_address: email
           ) do
        %EmailIntegration{} = existing ->
          existing
          |> EmailIntegration.changeset(%{
            provider: :gmail,
            email_address: email,
            sync_enabled: true
          })
          |> EmailIntegration.token_changeset(preserve_refresh_token(existing, token_attrs))
          |> Repo.update()

        nil ->
          %EmailIntegration{organization_id: scope.org.id, user_id: scope.user.id}
          |> EmailIntegration.changeset(%{provider: :gmail, email_address: email})
          |> EmailIntegration.token_changeset(token_attrs)
          |> Repo.insert()
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Email Integrations
  # ---------------------------------------------------------------------------

  @doc """
  Returns all email integrations for the scope's org.
  """
  def list_integrations(scope) do
    EmailIntegration
    |> where(organization_id: ^scope.org.id)
    |> order_by(desc: :is_primary, asc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single integration scoped to org.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_integration!(scope, id) do
    EmailIntegration
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> Repo.one!()
  end

  @doc """
  Creates an email integration record (no OAuth yet — tokens added later).
  """
  def create_integration(scope, attrs \\ %{}) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      %EmailIntegration{
        organization_id: scope.org.id,
        user_id: scope.user.id
      }
      |> EmailIntegration.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates OAuth tokens on an integration. Called by the OAuth callback controller.
  """
  def store_tokens(scope, %EmailIntegration{} = integration, token_attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      integration
      |> EmailIntegration.token_changeset(preserve_refresh_token(integration, token_attrs))
      |> Repo.update()
    end
  end

  @doc """
  Marks an integration as the primary one for the org.
  Clears the primary flag from all others first.
  """
  def set_primary(scope, %EmailIntegration{} = integration) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      Repo.transaction(fn ->
        EmailIntegration
        |> where(organization_id: ^scope.org.id)
        |> Repo.update_all(set: [is_primary: false])

        integration
        |> Ecto.Changeset.change(is_primary: true)
        |> Repo.update!()
      end)
    end
  end

  @doc """
  Toggles sync on/off for an integration.
  """
  def toggle_sync(scope, %EmailIntegration{} = integration) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      integration
      |> Ecto.Changeset.change(sync_enabled: !integration.sync_enabled)
      |> Repo.update()
    end
  end

  @doc """
  Deletes an email integration.
  """
  def delete_integration(scope, %EmailIntegration{} = integration) do
    if integration.organization_id == scope.org.id do
      case authorize_integration_delete(scope, integration) do
        :ok -> Repo.delete(integration)
        {:error, _reason} = error -> error
      end
    else
      {:error, :unauthorized}
    end
  end

  def enqueue_gmail_backfill(scope, %EmailIntegration{} = integration, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}),
         true <- integration.organization_id == scope.org.id,
         true <- integration.provider == :gmail,
         true <- integration.sync_enabled,
         {:ok, query} <- GmailBackfillWorker.build_query(attrs) do
      job_attrs = %{
        "integration_id" => integration.id,
        "organization_id" => scope.org.id,
        "requested_by_id" => scope.user.id,
        "query" => query
      }

      job_attrs
      |> GmailBackfillWorker.new(
        unique: [
          period: 300,
          fields: [:worker, :args],
          keys: [:integration_id, :query],
          states: [:available, :scheduled, :executing, :retryable]
        ]
      )
      |> then(&Oban.insert(Konevo.Oban, &1))
      |> mark_gmail_backfill_queued(integration)
    else
      false -> {:error, :invalid_integration}
      error -> error
    end
  end

  defp mark_gmail_backfill_queued({:ok, job}, integration) do
    attrs = %{
      history_import_status: "queued",
      history_import_started_at: nil,
      history_import_completed_at: nil,
      history_imported_threads: 0,
      history_processed_threads: 0,
      history_import_error: nil
    }

    case integration |> EmailIntegration.history_import_changeset(attrs) |> Repo.update() do
      {:ok, _integration} -> {:ok, job}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp mark_gmail_backfill_queued(error, _integration), do: error

  @doc """
  Enqueues an immediate Gmail sync for the active integration in the scope's org.
  """
  def enqueue_gmail_sync(scope) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}),
         {:ok, integration} <- get_active_gmail_integration(scope) do
      %{"integration_id" => integration.id}
      |> GmailSyncWorker.new(
        unique: [
          period: 30,
          fields: [:worker, :args],
          keys: [:integration_id]
        ]
      )
      |> then(&Oban.insert(Konevo.Oban, &1))
    end
  end

  @doc """
  Returns a changeset for tracking integration changes.
  """
  def change_integration(%EmailIntegration{} = integration, attrs \\ %{}) do
    EmailIntegration.changeset(integration, attrs)
  end

  def change_integration_signature(%EmailIntegration{} = integration, attrs \\ %{}) do
    integration
    |> EmailIntegration.branding_changeset(EmailBranding.sanitize_attrs(attrs))
  end

  def update_integration_signature(scope, %EmailIntegration{} = integration, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}),
         true <- integration.organization_id == scope.org.id do
      integration
      |> change_integration_signature(attrs)
      |> Repo.update()
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  def fetch_gmail_primary_signature(scope, %EmailIntegration{} = integration) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}),
         true <- integration.organization_id == scope.org.id,
         true <- integration.provider == :gmail,
         true <- integration.sync_enabled,
         {:ok, access_token} <- refresh_integration_token(integration) do
      GmailClient.fetch_primary_signature(access_token)
    else
      false -> {:error, :invalid_integration}
      error -> error
    end
  end

  def import_gmail_primary_signature(scope, %EmailIntegration{} = integration) do
    with {:ok, signature} <- fetch_gmail_primary_signature(scope, integration) do
      update_integration_signature(scope, integration, %{signature_html: signature})
    end
  end

  @doc """
  Lists Google Calendar events from the active Google Workspace integration.
  """
  def list_google_calendar_events(scope, starts_at, ends_at) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}),
         {:ok, integration} <- get_active_gmail_integration(scope),
         {:ok, access_token} <- refresh_integration_token(integration),
         {:ok, %{"items" => items}} <-
           GmailClient.list_calendar_events(access_token, starts_at, ends_at, max_results: 2500) do
      {:ok, items}
    end
  end

  # ---------------------------------------------------------------------------
  # Email Threads
  # ---------------------------------------------------------------------------

  @doc """
  Returns email threads for the scope's org.

  Options:
    - `:category`      – atom to filter by category
    - `:unresolved`    – boolean; true returns only unresolved threads
    - `:contact_id`    – filter by linked contact
    - `:deal_id`       – filter by linked deal
    - `:sort_by`       – `:last_activity_at` | `:last_inbound_at` | `:revenue_at_risk`
    - `:sort_dir`      – `:asc` | `:desc`
    - `:page`          – 1-based integer
    - `:per_page`      – integer (defaults to 25)

  Returns `{threads, total_count}`.
  """
  def list_threads(scope, opts \\ []) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      page = Keyword.get(opts, :page, 1)
      per_page = Keyword.get(opts, :per_page, 25)

      filtered =
        scope
        |> thread_base_query()
        |> filter_view(Keyword.get(opts, :view, :inbox))
        |> filter_category(Keyword.get(opts, :category))
        |> filter_search(Keyword.get(opts, :search))
        |> filter_unresolved(Keyword.get(opts, :unresolved))
        |> filter_thread_contact(Keyword.get(opts, :contact_id))
        |> filter_thread_deal(Keyword.get(opts, :deal_id))

      total = Repo.aggregate(filtered, :count, :id)

      threads =
        filtered
        |> with_email_count()
        |> sort_threads(
          Keyword.get(opts, :sort_by, :last_activity_at),
          Keyword.get(opts, :sort_dir, :desc)
        )
        |> limit(^per_page)
        |> offset(^((page - 1) * per_page))
        |> preload([:contact, :deal])
        |> Repo.all()

      {threads, total}
    end
  end

  @doc """
  Returns the unresolved queue — threads needing attention, ranked by urgency.

  Urgency = revenue_at_risk × days since last inbound (or just days if no deal).
  """
  def unresolved_queue(scope, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    now = DateTime.utc_now(:second)

    from(t in EmailThread,
      where: t.organization_id == ^scope.org.id,
      where: t.is_unresolved == true,
      where: t.is_archived == false,
      where: is_nil(t.trashed_at),
      where: t.category in [:lead, :customer],
      order_by: [
        desc:
          fragment(
            "COALESCE(?, 0) * EXTRACT(EPOCH FROM (? - COALESCE(?, ?))) / 86400",
            t.revenue_at_risk,
            ^now,
            t.last_inbound_at,
            t.inserted_at
          )
      ],
      limit: ^limit,
      preload: [:contact, :deal]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single email thread scoped to org, preloading emails.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_thread!(scope, id) do
    EmailThread
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> preload([:contact, :deal, emails: ^from(e in Email, order_by: [asc: e.received_at])])
    |> Repo.one!()
  end

  @doc """
  Gets a single email thread scoped to org for list-row updates.
  """
  def get_thread_for_list!(scope, id) do
    EmailThread
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> preload([:contact, :deal])
    |> Repo.one!()
  end

  @doc """
  Creates an email thread. Typically called by the email sync worker.
  """
  def create_thread(scope, attrs \\ %{}) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      %EmailThread{organization_id: scope.org.id}
      |> EmailThread.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates an email thread (e.g., set category after AI processing).
  """
  def update_thread(scope, %EmailThread{} = thread, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}),
         true <- thread.organization_id == scope.org.id do
      thread
      |> EmailThread.changeset(attrs)
      |> Repo.update()
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc """
  Marks a thread as resolved (human replied or manually resolved).
  """
  def resolve_thread(scope, %EmailThread{} = thread) do
    update_thread(scope, thread, %{is_unresolved: false})
  end

  @doc """
  Archives a thread.
  """
  def archive_thread(scope, %EmailThread{} = thread) do
    update_thread(scope, thread, %{is_archived: true, is_unresolved: false, trashed_at: nil})
  end

  @doc """
  Moves an archived thread back to the active inbox.
  """
  def unarchive_thread(scope, %EmailThread{} = thread) do
    update_thread(scope, thread, %{is_archived: false, trashed_at: nil})
  end

  @doc """
  Toggles the local favorite/star state.
  """
  def toggle_favorite(scope, %EmailThread{} = thread) do
    update_thread(scope, thread, %{is_favorite: !thread.is_favorite})
  end

  @doc """
  Sets the local CRM category for a thread.
  """
  def categorize_thread(scope, %EmailThread{} = thread, category)
      when category in [nil, :lead, :customer, :support, :billing, :internal] do
    update_thread(scope, thread, %{category: category})
  end

  def categorize_thread(_scope, %EmailThread{}, _category), do: {:error, :invalid_category}

  @doc """
  Marks a thread as read locally and in Gmail.
  """
  def mark_read(scope, %EmailThread{} = thread) do
    update_thread_read_state(scope, thread, true)
  end

  @doc """
  Marks a thread as unread locally and in Gmail.
  """
  def mark_unread(scope, %EmailThread{} = thread) do
    update_thread_read_state(scope, thread, false)
  end

  @doc false
  def sync_gmail_thread_read_state(thread_id, read?) when is_integer(thread_id) do
    with %EmailThread{thread_id_gmail: gmail_thread_id, organization_id: organization_id}
         when is_binary(gmail_thread_id) <- Repo.get(EmailThread, thread_id),
         %EmailIntegration{} = integration <- active_gmail_integration(organization_id),
         {:ok, access_token} <- refresh_integration_token(integration),
         {:ok, _thread} <-
           GmailClient.modify_thread_labels(access_token, gmail_thread_id,
             add_label_ids: if(read?, do: [], else: ["UNREAD"]),
             remove_label_ids: if(read?, do: ["UNREAD"], else: [])
           ) do
      :ok
    else
      nil -> :ok
      %EmailThread{} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Moves a thread to the local bin without touching the provider mailbox.
  """
  def move_to_bin(scope, %EmailThread{} = thread) do
    update_thread(scope, thread, %{
      trashed_at: DateTime.utc_now(:second),
      is_archived: false,
      is_unresolved: false
    })
  end

  @doc """
  Restores a locally binned thread to the active inbox.
  """
  def restore_thread(scope, %EmailThread{} = thread) do
    update_thread(scope, thread, %{trashed_at: nil, is_archived: false})
  end

  @doc """
  Links a thread to a contact. Overwrites any existing link.
  """
  def link_contact(scope, %EmailThread{} = thread, contact_id) do
    update_thread(scope, thread, %{contact_id: contact_id})
  end

  @doc """
  Links a thread to a deal.
  """
  def link_deal(scope, %EmailThread{} = thread, deal_id) do
    update_thread(scope, thread, %{deal_id: deal_id})
  end

  @doc """
  Returns a changeset for tracking thread changes.
  """
  def change_thread(%EmailThread{} = thread, attrs \\ %{}) do
    EmailThread.changeset(thread, attrs)
  end

  # ---------------------------------------------------------------------------
  # Scheduled Emails
  # ---------------------------------------------------------------------------

  @doc """
  Returns scheduled emails for the scope's org.

  Options:
    - `:status`   - filter by status
    - `:page`     - 1-based integer
    - `:per_page` - integer

  Returns `{scheduled_emails, total_count}`.
  """
  def list_scheduled_emails(scope, opts \\ []) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      page = Keyword.get(opts, :page, 1)
      per_page = Keyword.get(opts, :per_page, 25)

      filtered =
        scope
        |> scheduled_email_base_query()
        |> filter_scheduled_status(Keyword.get(opts, :status))
        |> filter_scheduled_search(Keyword.get(opts, :search))

      total = Repo.aggregate(filtered, :count, :id)

      scheduled_emails =
        filtered
        |> order_by(desc: :inserted_at)
        |> limit(^per_page)
        |> offset(^((page - 1) * per_page))
        |> preload([:email_thread, :scheduled_by])
        |> Repo.all()

      {scheduled_emails, total}
    end
  end

  @doc """
  Returns a scoped scheduled email.
  """
  def get_scheduled_email!(scope, id) do
    ScheduledEmail
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> preload([:email_thread, :scheduled_by])
    |> Repo.one!()
  end

  @doc """
  Returns scheduled email counts grouped by status.
  """
  def count_scheduled_emails_by_status(scope) do
    scope
    |> scheduled_email_base_query()
    |> group_by([s], s.status)
    |> select([s], {s.status, count(s.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Schedules a new outbound Gmail message.
  """
  def schedule_message(scope, attrs) do
    attachment_ids = value_for(attrs, :attachment_ids) || []
    attachment_owner_id = value_for(attrs, :attachment_owner_id)

    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}),
         {:ok, _integration} <- get_active_gmail_integration(scope),
         {:ok, recipients} <- normalize_recipients(attrs),
         {:ok, body} <- required_body(attrs),
         {:ok, attachment_attrs} <-
           scheduled_attachment_attrs(scope, attachment_owner_id, attachment_ids),
         {:ok, scheduled_at} <- normalize_scheduled_at(value_for(attrs, :scheduled_at)) do
      subject = attrs |> value_for(:subject) |> blank_to_subject()

      insert_scheduled_email(
        scope,
        Map.merge(
          %{
            kind: :new_message,
            to: recipients.to,
            cc: recipients.cc,
            bcc: recipients.bcc,
            subject: subject,
            body: body,
            scheduled_at: scheduled_at,
            status: :pending
          },
          attachment_attrs
        )
      )
    end
  end

  @doc """
  Schedules a reply to an existing Gmail thread.
  """
  def schedule_reply(scope, %EmailThread{} = thread, reply_body, scheduled_at, opts \\ []) do
    attachment_ids = Keyword.get(opts, :attachment_ids, [])
    attachment_owner_id = Keyword.get(opts, :attachment_owner_id)

    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}),
         true <- thread.organization_id == scope.org.id,
         {:ok, integration} <- get_active_gmail_integration(scope),
         {:ok, body} <- required_body(%{body: reply_body}),
         {:ok, scheduled_at} <- normalize_scheduled_at(scheduled_at),
         {:ok, attachment_attrs} <-
           scheduled_attachment_attrs(scope, attachment_owner_id, attachment_ids),
         {:ok, to_address} <- required_reply_recipient(thread, integration.email_address) do
      insert_scheduled_email(
        scope,
        Map.merge(
          %{
            kind: :reply,
            email_thread_id: thread.id,
            to: [to_address],
            cc: [],
            bcc: [],
            subject: reply_subject(thread.subject),
            body: body,
            in_reply_to: get_last_message_id(thread),
            gmail_thread_id: thread.thread_id_gmail,
            scheduled_at: scheduled_at,
            status: :pending
          },
          attachment_attrs
        )
      )
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc """
  Cancels a pending scheduled email.
  """
  def cancel_scheduled_email(scope, %ScheduledEmail{} = scheduled_email) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}),
         true <- scheduled_email.organization_id == scope.org.id,
         true <- scheduled_email.status == :pending do
      case scheduled_email
           |> Ecto.Changeset.change(status: :cancelled, cancelled_at: DateTime.utc_now(:second))
           |> Repo.update() do
        {:ok, cancelled} ->
          delete_scheduled_draft_attachments(scope, cancelled)
          {:ok, cancelled}

        error ->
          error
      end
    else
      false -> {:error, :not_pending}
      error -> error
    end
  end

  @doc false
  def deliver_scheduled_email(scheduled_email_id, opts \\ []) do
    Repo.transaction(fn ->
      ScheduledEmail
      |> where(id: ^scheduled_email_id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> preload_scheduled_delivery()
      |> deliver_scheduled_email_record(opts)
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def deliver_due_scheduled_emails(limit \\ 50) do
    now = DateTime.utc_now(:second)

    ScheduledEmail
    |> where([s], s.status == :pending and s.scheduled_at <= ^now)
    |> order_by(asc: :scheduled_at)
    |> limit(^limit)
    |> select([s], s.id)
    |> Repo.all()
    |> Enum.map(&deliver_scheduled_email(&1, mark_failed?: true))
  end

  # ---------------------------------------------------------------------------
  # Emails
  # ---------------------------------------------------------------------------

  @doc """
  Stores a single email. Typically called by the email sync worker.
  Idempotent — returns `{:ok, email}` or `{:ok, existing}` if already stored.
  """
  def store_email(scope, %EmailThread{} = thread, attrs) do
    case Repo.get_by(Email, message_id: attrs[:message_id] || attrs["message_id"]) do
      %Email{} = existing ->
        {:ok, existing}

      nil ->
        Repo.transaction(fn ->
          email =
            %Email{organization_id: scope.org.id, thread_id: thread.id}
            |> Email.changeset(attrs)
            |> Repo.insert!()

          update_thread_after_email(thread, email)
          email
        end)
    end
  end

  @doc """
  Returns all emails in a thread ordered by received_at ascending.
  """
  def list_emails(%EmailThread{} = thread) do
    Email
    |> where(thread_id: ^thread.id)
    |> order_by(asc: :received_at)
    |> Repo.all()
  end

  @doc """
  Gets a single email by id, scoped to org.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_email!(scope, id) do
    Email
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> Repo.one!()
  end

  defp scheduled_email_base_query(%{org: %{id: org_id}}) do
    from(s in ScheduledEmail, where: s.organization_id == ^org_id)
  end

  defp filter_scheduled_status(query, nil), do: query
  defp filter_scheduled_status(query, status), do: from(s in query, where: s.status == ^status)

  defp filter_scheduled_search(query, nil), do: query
  defp filter_scheduled_search(query, ""), do: query

  defp filter_scheduled_search(query, search) when is_binary(search) do
    case String.trim(search) do
      "" ->
        query

      term ->
        pattern = "%#{term}%"

        from(s in query,
          where:
            ilike(s.subject, ^pattern) or ilike(s.body, ^pattern) or
              ilike(fragment("array_to_string(?, ' ')", s.to), ^pattern) or
              ilike(fragment("array_to_string(?, ' ')", s.cc), ^pattern) or
              ilike(fragment("array_to_string(?, ' ')", s.bcc), ^pattern)
        )
    end
  end

  defp insert_scheduled_email(scope, attrs) do
    changeset =
      %ScheduledEmail{
        organization_id: scope.org.id,
        scheduled_by_id: scope.user.id
      }
      |> ScheduledEmail.changeset(attrs)

    if changeset.valid? do
      Repo.transaction(fn ->
        scheduled_email = Repo.insert!(changeset)

        {:ok, job} =
          %{"scheduled_email_id" => scheduled_email.id}
          |> ScheduledEmailWorker.new(scheduled_at: scheduled_email.scheduled_at)
          |> then(&Oban.insert(Konevo.Oban, &1))

        scheduled_email
        |> Ecto.Changeset.change(oban_job_id: job.id)
        |> Repo.update!()
      end)
    else
      {:error, changeset}
    end
  end

  defp deliver_scheduled_email_record(nil, _opts), do: {:ok, :not_found}

  defp deliver_scheduled_email_record(%ScheduledEmail{status: status} = scheduled_email, _opts)
       when status in [:sent, :cancelled] do
    {:ok, scheduled_email}
  end

  defp deliver_scheduled_email_record(%ScheduledEmail{status: :pending} = scheduled_email, opts) do
    scope = scheduled_scope(scheduled_email)

    with {:ok, integration} <- get_active_gmail_integration(scope),
         {:ok, access_token} <- refresh_integration_token(integration),
         {:ok, attachments} <- scheduled_attachments(scope, scheduled_email),
         {:ok, msg_id, response} <-
           send_scheduled_email(scheduled_email, integration, access_token, attachments),
         {:ok, _stored} <-
           store_scheduled_email(scheduled_email, integration, msg_id, response, attachments) do
      mark_scheduled_sent(scheduled_email, msg_id)
    else
      {:error, reason} ->
        if Keyword.get(opts, :mark_failed?, true) do
          mark_scheduled_failed(scheduled_email, reason)
        end

        {:error, reason}
    end
  end

  defp deliver_scheduled_email_record(%ScheduledEmail{} = scheduled_email, _opts),
    do: {:ok, scheduled_email}

  defp preload_scheduled_delivery(nil), do: nil

  defp preload_scheduled_delivery(%ScheduledEmail{} = scheduled_email) do
    Repo.preload(scheduled_email, [:organization, :scheduled_by, email_thread: [:emails]])
  end

  defp send_scheduled_email(scheduled_email, integration, access_token, attachments) do
    body = branded_body(scheduled_email.body, integration)

    raw =
      build_rfc2822(
        integration.email_address,
        scheduled_recipients(scheduled_email),
        scheduled_email.subject || "(no subject)",
        body,
        scheduled_email.in_reply_to,
        attachments
      )

    opts =
      case scheduled_email.gmail_thread_id do
        nil -> []
        thread_id -> [thread_id: thread_id]
      end

    case GmailClient.send_message(access_token, raw, opts) do
      {:ok, %{"id" => msg_id} = response} -> {:ok, msg_id, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp store_scheduled_email(
         %ScheduledEmail{kind: :new_message} = scheduled_email,
         integration,
         msg_id,
         response,
         attachments
       ) do
    scope = scheduled_scope(scheduled_email)
    body = branded_body(scheduled_email.body, integration)

    create_sent_thread(
      scope,
      %{
        from: integration.email_address,
        recipients: scheduled_recipients(scheduled_email),
        subject: scheduled_email.subject || "(no subject)",
        body: body,
        msg_id: msg_id,
        response: response,
        attachments: attachments
      },
      scheduled_attachment_claim(scheduled_email)
    )
  end

  defp store_scheduled_email(
         %ScheduledEmail{kind: :reply} = scheduled_email,
         integration,
         msg_id,
         _response,
         attachments
       ) do
    body = branded_body(scheduled_email.body, integration)

    store_outbound_email(
      scheduled_scope(scheduled_email),
      scheduled_email.email_thread,
      %{
        message_id: msg_id,
        from: integration.email_address,
        to: scheduled_email.to,
        cc: scheduled_email.cc,
        bcc: scheduled_email.bcc,
        subject: scheduled_email.subject,
        body: body_text(body),
        html_body: html_body(body),
        has_attachments: attachments != []
      },
      scheduled_attachment_claim(scheduled_email)
    )
  end

  defp scheduled_recipients(scheduled_email) do
    %{
      to: scheduled_email.to || [],
      cc: scheduled_email.cc || [],
      bcc: scheduled_email.bcc || []
    }
  end

  defp scheduled_scope(%ScheduledEmail{} = scheduled_email) do
    %Scope{org: scheduled_email.organization, user: scheduled_email.scheduled_by}
  end

  defp scheduled_attachment_attrs(_scope, _draft_owner_id, nil),
    do: {:ok, %{attachment_owner_id: nil, attachment_ids: []}}

  defp scheduled_attachment_attrs(_scope, _draft_owner_id, []),
    do: {:ok, %{attachment_owner_id: nil, attachment_ids: []}}

  defp scheduled_attachment_attrs(scope, draft_owner_id, file_ids)
       when is_binary(draft_owner_id) and draft_owner_id != "" do
    with {:ok, file_ids} <- normalize_attachment_ids(file_ids),
         {:ok, files} <- Uploads.list_email_draft_attachments(scope, draft_owner_id),
         true <- draft_file_ids_present?(file_ids, files) do
      {:ok, %{attachment_owner_id: draft_owner_id, attachment_ids: file_ids}}
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  defp scheduled_attachment_attrs(_scope, _draft_owner_id, _file_ids),
    do: {:error, :missing_attachment_owner}

  defp scheduled_attachments(_scope, %ScheduledEmail{attachment_ids: []}), do: {:ok, []}
  defp scheduled_attachments(_scope, %ScheduledEmail{attachment_ids: nil}), do: {:ok, []}

  defp scheduled_attachments(scope, %ScheduledEmail{} = scheduled_email) do
    draft_attachments(
      scope,
      scheduled_email.attachment_owner_id,
      scheduled_email.attachment_ids || []
    )
  end

  defp scheduled_attachment_claim(%ScheduledEmail{} = scheduled_email) do
    attachment_claim(scheduled_email.attachment_owner_id, scheduled_email.attachment_ids || [])
  end

  defp delete_scheduled_draft_attachments(_scope, %ScheduledEmail{attachment_ids: []}), do: :ok
  defp delete_scheduled_draft_attachments(_scope, %ScheduledEmail{attachment_ids: nil}), do: :ok

  defp delete_scheduled_draft_attachments(_scope, %ScheduledEmail{attachment_owner_id: nil}),
    do: :ok

  defp delete_scheduled_draft_attachments(_scope, %ScheduledEmail{attachment_owner_id: ""}),
    do: :ok

  defp delete_scheduled_draft_attachments(scope, %ScheduledEmail{} = scheduled_email) do
    Enum.each(scheduled_email.attachment_ids, fn file_id ->
      Uploads.delete_email_draft_attachment(scope, file_id, scheduled_email.attachment_owner_id)
    end)

    :ok
  end

  defp draft_file_ids_present?(file_ids, files) do
    available_ids = files |> Enum.map(& &1.id) |> MapSet.new()
    file_ids |> MapSet.new() |> MapSet.subset?(available_ids)
  end

  defp normalize_attachment_ids(nil), do: {:ok, []}
  defp normalize_attachment_ids([]), do: {:ok, []}

  defp normalize_attachment_ids(file_ids) when is_list(file_ids) do
    file_ids
    |> Enum.reduce_while({:ok, []}, fn file_id, {:ok, acc} ->
      case normalize_attachment_id(file_id) do
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        :error -> {:halt, {:error, :invalid_file_id}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, ids |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  defp normalize_attachment_ids(file_id), do: normalize_attachment_ids([file_id])

  defp normalize_attachment_id(file_id) when is_integer(file_id) and file_id > 0,
    do: {:ok, file_id}

  defp normalize_attachment_id(file_id) do
    case Integer.parse(to_string(file_id)) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> :error
    end
  end

  defp mark_scheduled_sent(scheduled_email, msg_id) do
    scheduled_email
    |> Ecto.Changeset.change(
      status: :sent,
      sent_at: DateTime.utc_now(:second),
      external_message_id: msg_id,
      failure_reason: nil
    )
    |> Repo.update()
  end

  defp mark_scheduled_failed(scheduled_email, reason) do
    scheduled_email
    |> Ecto.Changeset.change(
      status: :failed,
      failed_at: DateTime.utc_now(:second),
      failure_reason: inspect(reason)
    )
    |> Repo.update()
  end

  defp update_thread_after_email(%EmailThread{} = thread, %Email{} = email) do
    attrs =
      if email.is_inbound do
        %{
          read_at: nil,
          is_unresolved: true,
          is_archived: false,
          trashed_at: nil,
          snippet: email_snippet(email),
          participants: latest_participants(thread, email),
          last_inbound_at: email.received_at,
          last_activity_at: email.received_at,
          has_attachments: thread.has_attachments or email.has_attachments
        }
      else
        %{
          read_at: DateTime.utc_now(:second),
          is_unresolved: false,
          snippet: email_snippet(email),
          participants: latest_participants(thread, email),
          last_outbound_at: email.received_at,
          last_activity_at: email.received_at,
          has_attachments: thread.has_attachments or email.has_attachments
        }
      end

    updated =
      thread
      |> EmailThread.changeset(attrs)
      |> Repo.update!()

    stop_automation_after_inbound_reply(updated, email)
  end

  defp stop_automation_after_inbound_reply(%EmailThread{} = thread, %Email{is_inbound: true}) do
    {:ok, _count} =
      Automation.cancel_active_executions_for_contact_id(
        thread.organization_id,
        thread.contact_id
      )

    thread
  end

  defp stop_automation_after_inbound_reply(%EmailThread{} = thread, _email), do: thread

  defp email_snippet(%Email{} = email) do
    [email.body, email.html_body, email.subject]
    |> Enum.find_value(&snippet_text/1)
    |> case do
      nil -> ""
      snippet -> String.slice(snippet, 0, 250)
    end
  end

  defp snippet_text(nil), do: nil

  defp snippet_text(value) do
    value =
      value
      |> body_text()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    if value == "", do: nil, else: value
  end

  defp latest_participants(%EmailThread{} = thread, %Email{} = email) do
    [email.from | thread.participants || []]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # ---------------------------------------------------------------------------
  # Stats
  # ---------------------------------------------------------------------------

  @doc """
  Returns thread counts grouped by category for the scope's org.
  """
  def count_threads_by_category(scope, opts \\ []) do
    scope
    |> thread_base_query()
    |> filter_view(Keyword.get(opts, :view, :inbox))
    |> filter_search(Keyword.get(opts, :search))
    |> filter_unresolved(Keyword.get(opts, :unresolved))
    |> group_by([t], t.category)
    |> select([t], {t.category, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns counts for the inbox sidebar views.
  """
  def count_threads_by_view(scope) do
    base = thread_base_query(scope)

    %{
      inbox: base |> filter_view(:inbox) |> Repo.aggregate(:count, :id),
      favorites: base |> filter_view(:favorites) |> Repo.aggregate(:count, :id),
      sent: base |> filter_view(:sent) |> Repo.aggregate(:count, :id),
      archived: base |> filter_view(:archived) |> Repo.aggregate(:count, :id),
      bin: base |> filter_view(:bin) |> Repo.aggregate(:count, :id)
    }
  end

  @doc """
  Returns total revenue at risk across all unresolved lead/customer threads.
  """
  def total_revenue_at_risk(scope) do
    EmailThread
    |> where(organization_id: ^scope.org.id)
    |> where(is_unresolved: true)
    |> where(is_archived: false)
    |> where([t], is_nil(t.trashed_at))
    |> where([t], t.category in [:lead, :customer])
    |> select([t], coalesce(sum(t.revenue_at_risk), 0))
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp thread_base_query(%{org: %{id: org_id}}) do
    from(t in EmailThread, where: t.organization_id == ^org_id)
  end

  defp authorize_integration_delete(scope, %EmailIntegration{user_id: user_id})
       when user_id == scope.user.id,
       do: :ok

  defp authorize_integration_delete(scope, _integration) do
    Bodyguard.permit(Policy, :delete, scope.user, %{org: scope.org})
  end

  defp update_thread_read_state(scope, thread, read?) do
    attrs = %{read_at: if(read?, do: DateTime.utc_now(:second), else: nil)}

    with {:ok, updated} <- update_thread(scope, thread, attrs) do
      enqueue_gmail_thread_read_state(updated, read?)
      {:ok, updated}
    end
  end

  defp enqueue_gmail_thread_read_state(%EmailThread{thread_id_gmail: nil}, _read?), do: :ok

  defp enqueue_gmail_thread_read_state(%EmailThread{id: thread_id}, read?) do
    case GmailThreadReadStateWorker.enqueue(thread_id, read?) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Inbox: failed to sync Gmail read state: #{inspect(reason)}")
    end
  end

  defp with_email_count(query) do
    email_counts =
      from(e in Email,
        group_by: e.thread_id,
        select: %{thread_id: e.thread_id, email_count: count(e.id)}
      )

    from(t in query,
      left_join: c in subquery(email_counts),
      on: c.thread_id == t.id,
      select_merge: %{email_count: coalesce(c.email_count, 0)}
    )
  end

  defp filter_view(query, :favorites),
    do: from(t in query, where: is_nil(t.trashed_at) and t.is_favorite == true)

  defp filter_view(query, :sent),
    do: from(t in query, where: is_nil(t.trashed_at) and not is_nil(t.last_outbound_at))

  defp filter_view(query, :archived),
    do: from(t in query, where: is_nil(t.trashed_at) and t.is_archived == true)

  defp filter_view(query, :bin), do: from(t in query, where: not is_nil(t.trashed_at))

  defp filter_view(query, _view),
    do: from(t in query, where: is_nil(t.trashed_at) and t.is_archived == false)

  defp filter_category(query, nil), do: query
  defp filter_category(query, :uncategorised), do: from(t in query, where: is_nil(t.category))
  defp filter_category(query, cat), do: from(t in query, where: t.category == ^cat)

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query

  defp filter_search(query, search) when is_binary(search) do
    pattern = "%#{String.trim(search)}%"

    from(t in query,
      where:
        ilike(t.subject, ^pattern) or ilike(t.snippet, ^pattern) or
          ilike(fragment("array_to_string(?, ' ')", t.participants), ^pattern)
    )
  end

  defp filter_unresolved(query, true), do: from(t in query, where: t.is_unresolved == true)
  defp filter_unresolved(query, false), do: from(t in query, where: t.is_unresolved == false)
  defp filter_unresolved(query, _), do: query

  defp filter_thread_contact(query, nil), do: query
  defp filter_thread_contact(query, id), do: from(t in query, where: t.contact_id == ^id)

  defp filter_thread_deal(query, nil), do: query
  defp filter_thread_deal(query, id), do: from(t in query, where: t.deal_id == ^id)

  defp sort_threads(query, :revenue_at_risk, dir),
    do: from(t in query, order_by: [{^dir, t.revenue_at_risk}])

  defp sort_threads(query, :last_activity_at, dir),
    do: from(t in query, order_by: [{^dir, t.last_activity_at}])

  defp sort_threads(query, _field, dir),
    do: from(t in query, order_by: [{^dir, t.last_activity_at}])

  # ---------------------------------------------------------------------------
  # Reply sending
  # ---------------------------------------------------------------------------

  @doc """
  Sends a reply to a Gmail thread using the org's active Gmail integration.

  Builds and sends an RFC2822 message, threads it in Gmail, and stores the sent
  email locally. Returns `{:ok, email}` or `{:error, reason}`.
  """
  def send_reply(scope, thread_or_id, reply_body, opts \\ [])

  def send_reply(scope, thread_id, reply_body, opts) when is_integer(thread_id) do
    thread =
      Repo.one(
        from(t in EmailThread,
          where: t.id == ^thread_id and t.organization_id == ^scope.org.id
        )
      )

    case thread do
      nil -> {:error, :not_found}
      thread -> send_reply(scope, get_thread!(scope, thread.id), reply_body, opts)
    end
  end

  def send_reply(scope, %EmailThread{} = thread, reply_body, opts) do
    attachment_ids = Keyword.get(opts, :attachment_ids, [])
    draft_owner_id = Keyword.get(opts, :attachment_owner_id)

    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}),
         {:ok, attachments} <- draft_attachments(scope, draft_owner_id, attachment_ids),
         {:ok, integration} <- get_active_gmail_integration(scope),
         {:ok, access_token} <- refresh_integration_token(integration),
         {:ok, recipients} <-
           validate_recipients(%{
             to: [determine_reply_to(thread, integration.email_address)],
             cc: [],
             bcc: []
           }),
         {:ok, %{"id" => msg_id}} <-
           send_threaded_reply(
             access_token,
             integration.email_address,
             integration,
             thread,
             recipients,
             reply_body,
             attachments
           ) do
      from_address = integration.email_address
      subject = reply_subject(thread.subject)
      body = branded_body(reply_body, integration)

      store_outbound_email(
        scope,
        thread,
        %{
          message_id: msg_id,
          from: from_address,
          to: recipients.to,
          cc: [],
          bcc: [],
          subject: subject,
          body: body_text(body),
          html_body: html_body(body),
          has_attachments: attachments != []
        },
        attachment_claim(draft_owner_id, attachment_ids)
      )
    end
  end

  defp send_threaded_reply(
         access_token,
         from_address,
         integration,
         thread,
         recipients,
         reply_body,
         attachments
       ) do
    body = branded_body(reply_body, integration)

    raw =
      build_rfc2822(
        from_address,
        recipients,
        reply_subject(thread.subject),
        body,
        get_last_message_id(thread),
        attachments
      )

    GmailClient.send_message(access_token, raw, thread_id: thread.thread_id_gmail)
  end

  defp validate_recipients(%{to: to}) when to in [[], [""], [nil]],
    do: {:error, :missing_recipient}

  defp validate_recipients(recipients), do: {:ok, recipients}

  defp determine_reply_to(
         %EmailThread{emails: emails, participants: participants},
         integration_email
       ) do
    own_email = integration_email |> extract_email() |> String.downcase()
    loaded = loaded_emails(emails)

    loaded
    |> Enum.filter(& &1.is_inbound)
    |> Enum.max_by(& &1.received_at, DateTime, fn -> nil end)
    |> case do
      nil ->
        first_external_participant(participants, own_email)

      email ->
        email.from |> extract_email() |> blank_to_nil() ||
          first_external_participant(participants, own_email)
    end
  end

  defp loaded_emails(%Ecto.Association.NotLoaded{}), do: []
  defp loaded_emails(list) when is_list(list), do: list

  defp first_external_participant(participants, own_email) do
    participants
    |> Enum.map(&extract_email/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.find(&(String.downcase(&1) != own_email))
    |> case do
      nil -> ""
      email -> email
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp extract_email(nil), do: ""

  defp extract_email(value) do
    value = to_string(value)

    case Regex.run(~r/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i, value) do
      [email] -> String.downcase(email)
      _ -> ""
    end
  end

  @doc """
  Sends a new Gmail message and stores it as a local sent thread.
  """
  def send_message(scope, attrs) do
    attachment_ids = value_for(attrs, :attachment_ids) || []
    draft_owner_id = value_for(attrs, :attachment_owner_id)

    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}),
         {:ok, recipients} <- normalize_recipients(attrs),
         {:ok, body} <- required_body(attrs),
         {:ok, attachments} <- draft_attachments(scope, draft_owner_id, attachment_ids),
         {:ok, integration} <- get_active_gmail_integration(scope),
         {:ok, access_token} <- refresh_integration_token(integration) do
      subject = attrs |> value_for(:subject) |> blank_to_subject()
      body = branded_body(body, integration)
      raw = build_rfc2822(integration.email_address, recipients, subject, body, nil, attachments)

      with {:ok, %{"id" => msg_id} = response} <- GmailClient.send_message(access_token, raw) do
        create_sent_thread(
          scope,
          %{
            from: integration.email_address,
            recipients: recipients,
            subject: subject,
            body: body,
            msg_id: msg_id,
            response: response,
            attachments: attachments
          },
          attachment_claim(draft_owner_id, attachment_ids)
        )
      end
    end
  end

  @doc """
  Sends a system email through a specific connected Gmail integration.

  This is intended for app-owned workflows, such as support requests, where the
  sender is configured globally instead of being selected from the caller's org.
  """
  def send_system_message(%EmailIntegration{} = integration, attrs) do
    integration = Repo.preload(integration, [:organization, :user])

    with {:ok, recipients} <- normalize_recipients(attrs),
         {:ok, body} <- required_body(attrs),
         {:ok, access_token} <- refresh_integration_token(integration) do
      subject = attrs |> value_for(:subject) |> blank_to_subject()
      body = branded_body(body, integration)
      raw = build_rfc2822(integration.email_address, recipients, subject, body, nil, [])

      with {:ok, %{"id" => msg_id} = response} <- GmailClient.send_message(access_token, raw) do
        scope = %Scope{user: integration.user, org: integration.organization}

        create_sent_thread(
          scope,
          %{
            from: integration.email_address,
            recipients: recipients,
            subject: subject,
            body: body,
            msg_id: msg_id,
            response: response,
            attachments: []
          },
          attachment_claim(nil, [])
        )
      end
    end
  end

  defp create_sent_thread(
         scope,
         %{
           from: from,
           recipients: recipients,
           subject: subject,
           body: body,
           msg_id: msg_id,
           response: response,
           attachments: attachments
         },
         attachment_claim
       ) do
    now = DateTime.utc_now(:second)
    participants = [from | recipients.to] |> Enum.uniq()
    has_attachments = attachments != []

    result =
      Repo.transaction(fn ->
        thread =
          %EmailThread{organization_id: scope.org.id}
          |> EmailThread.changeset(%{
            thread_id_gmail: response["threadId"],
            subject: subject,
            snippet: body |> body_text() |> String.slice(0, 250),
            is_unresolved: false,
            is_archived: false,
            read_at: now,
            last_activity_at: now,
            last_outbound_at: now,
            participants: participants,
            has_attachments: has_attachments
          })
          |> Repo.insert!()

        email =
          %Email{organization_id: scope.org.id, thread_id: thread.id}
          |> Email.changeset(%{
            message_id: msg_id,
            from: from,
            to: recipients.to,
            cc: recipients.cc,
            bcc: recipients.bcc,
            subject: subject,
            body: body_text(body),
            html_body: html_body(body),
            received_at: now,
            is_inbound: false,
            has_attachments: has_attachments
          })
          |> Repo.insert!()

        claim_attachments!(scope, attachment_claim, email)
        email
      end)

    maybe_enqueue_no_reply_follow_up(result, scope.org.id)
  end

  defp store_outbound_email(scope, %EmailThread{} = thread, attrs, attachment_claim) do
    now = DateTime.utc_now(:second)

    result =
      Repo.transaction(fn ->
        email =
          %Email{organization_id: scope.org.id, thread_id: thread.id}
          |> Email.changeset(Map.merge(attrs, %{received_at: now, is_inbound: false}))
          |> Repo.insert!()

        thread
        |> EmailThread.changeset(%{
          is_unresolved: false,
          read_at: now,
          snippet: email_snippet(email),
          participants: latest_participants(thread, email),
          last_outbound_at: now,
          last_activity_at: now,
          has_attachments: thread.has_attachments or Map.get(attrs, :has_attachments, false)
        })
        |> Repo.update!()

        claim_attachments!(scope, attachment_claim, email)
        email
      end)

    maybe_enqueue_no_reply_follow_up(result, scope.org.id)
  end

  defp maybe_enqueue_no_reply_follow_up({:ok, _result} = result, organization_id) do
    case NoReplyFollowUpWorker.enqueue(organization_id) do
      :ok ->
        result

      {:error, reason} ->
        Logger.warning("Inbox: failed to enqueue no-reply follow-up: #{inspect(reason)}")
        result
    end
  end

  defp maybe_enqueue_no_reply_follow_up(result, _organization_id), do: result

  defp claim_attachments!(_scope, %{ids: []}, _email), do: []

  defp claim_attachments!(scope, %{draft_owner_id: draft_owner_id, ids: ids}, email) do
    case Uploads.claim_email_draft_attachments(scope, draft_owner_id, ids, email) do
      {:ok, files} -> files
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp draft_attachments(_scope, nil, []), do: {:ok, []}
  defp draft_attachments(_scope, "", []), do: {:ok, []}

  defp draft_attachments(scope, draft_owner_id, file_ids) when is_binary(draft_owner_id) do
    Uploads.email_draft_attachments_for_delivery(scope, draft_owner_id, file_ids)
  end

  defp draft_attachments(_scope, _draft_owner_id, []), do: {:ok, []}

  defp draft_attachments(_scope, _draft_owner_id, _file_ids),
    do: {:error, :missing_attachment_owner}

  defp attachment_claim(draft_owner_id, ids) when is_binary(draft_owner_id) do
    %{draft_owner_id: draft_owner_id, ids: List.wrap(ids)}
  end

  defp attachment_claim(_draft_owner_id, _ids), do: %{draft_owner_id: nil, ids: []}

  defp get_active_gmail_integration(scope) do
    case active_gmail_integration(scope.org.id) do
      nil -> {:error, :no_integration}
      integration -> {:ok, integration}
    end
  end

  defp active_gmail_integration(organization_id) do
    Repo.one(
      from(i in EmailIntegration,
        where: i.organization_id == ^organization_id,
        where: i.provider == :gmail,
        where: i.sync_enabled == true,
        order_by: [desc: i.is_primary, asc: i.inserted_at],
        limit: 1
      )
    )
  end

  defp refresh_integration_token(%EmailIntegration{} = integration) do
    if integration_token_expired?(integration) do
      integration
      |> refresh_access_token()
      |> handle_token_refresh(integration)
    else
      {:ok, integration.access_token}
    end
  end

  defp refresh_access_token(%EmailIntegration{} = integration) do
    GmailClient.refresh_access_token(integration.refresh_token)
  end

  defp handle_token_refresh(
         {:ok, %{"access_token" => new_token, "expires_in" => expires_in}},
         integration
       ) do
    expires_at = DateTime.add(DateTime.utc_now(:second), expires_in, :second)

    Repo.update_all(
      from(i in EmailIntegration, where: i.id == ^integration.id),
      set: [access_token: new_token, token_expires_at: expires_at]
    )

    {:ok, new_token}
  end

  defp handle_token_refresh({:error, reason}, integration) do
    if GmailClient.invalid_grant?(reason) do
      disable_integration_sync(integration)
      {:error, :gmail_reauthorization_required}
    else
      {:error, {:token_refresh_failed, reason}}
    end
  end

  defp disable_integration_sync(%EmailIntegration{} = integration) do
    Repo.update_all(
      from(i in EmailIntegration, where: i.id == ^integration.id),
      set: [sync_enabled: false]
    )

    :ok
  end

  defp integration_token_expired?(%EmailIntegration{token_expires_at: nil}), do: true

  defp integration_token_expired?(%EmailIntegration{token_expires_at: expires_at}) do
    buffer = DateTime.add(DateTime.utc_now(:second), 5 * 60, :second)
    DateTime.compare(expires_at, buffer) == :lt
  end

  defp get_last_message_id(%EmailThread{emails: emails}) do
    case emails do
      %Ecto.Association.NotLoaded{} ->
        nil

      list ->
        list
        |> Enum.max_by(& &1.received_at, DateTime, fn -> nil end)
        |> case do
          nil -> nil
          email -> get_in(email.headers || %{}, ["Message-ID"])
        end
    end
  end

  defp reply_subject(nil), do: "Re: (no subject)"

  defp reply_subject(subject),
    do: if(String.starts_with?(subject, "Re:"), do: subject, else: "Re: #{subject}")

  defp normalize_recipients(attrs) do
    recipients = %{
      to: recipients_for(attrs, :to),
      cc: recipients_for(attrs, :cc),
      bcc: recipients_for(attrs, :bcc)
    }

    cond do
      recipients.to == [] ->
        {:error, :missing_recipient}

      recipient_validation_errors(recipients) != %{} ->
        {:error, {:invalid_recipients, recipient_validation_errors(recipients)}}

      true ->
        {:ok, recipients}
    end
  end

  defp recipient_validation_errors(recipients) do
    recipients
    |> Enum.reduce(%{}, fn {field, addresses}, errors ->
      invalid_addresses = Enum.reject(addresses, &valid_recipient_email?/1)

      if invalid_addresses == [] do
        errors
      else
        Map.put(errors, field, invalid_addresses)
      end
    end)
  end

  defp valid_recipient_email?(email) do
    String.match?(email, ~r/^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$/)
  end

  defp recipients_for(attrs, key) do
    attrs
    |> value_for(key)
    |> case do
      nil -> []
      list when is_list(list) -> list
      value when is_binary(value) -> String.split(value, [",", ";"])
    end
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp required_body(attrs) do
    case attrs |> value_for(:body) |> to_string() |> String.trim() do
      "" -> {:error, :missing_body}
      body -> {:ok, body}
    end
  end

  defp required_reply_recipient(thread, integration_email) do
    case thread |> determine_reply_to(integration_email) |> to_string() |> String.trim() do
      "" -> {:error, :missing_recipient}
      recipient -> {:ok, recipient}
    end
  end

  defp normalize_scheduled_at(%DateTime{} = scheduled_at) do
    scheduled_at =
      scheduled_at
      |> DateTime.shift_zone!("Etc/UTC")
      |> DateTime.truncate(:second)

    if DateTime.compare(scheduled_at, next_schedulable_at()) in [:eq, :gt] do
      {:ok, scheduled_at}
    else
      {:error, :scheduled_at_too_soon}
    end
  end

  defp normalize_scheduled_at(value) when is_binary(value) do
    value = String.trim(value)

    with {:error, _reason} <- DateTime.from_iso8601(value),
         {:error, _reason} <- parse_local_scheduled_at(value) do
      {:error, :invalid_scheduled_at}
    else
      {:ok, scheduled_at, _offset} -> normalize_scheduled_at(scheduled_at)
      {:ok, scheduled_at} -> normalize_scheduled_at(scheduled_at)
    end
  end

  defp normalize_scheduled_at(_value), do: {:error, :invalid_scheduled_at}

  defp next_schedulable_at do
    now = DateTime.utc_now(:second)
    DateTime.add(now, 60 - now.second, :second)
  end

  defp parse_local_scheduled_at(value) do
    case value |> normalize_local_datetime_value() |> NaiveDateTime.from_iso8601() do
      {:ok, naive} -> {:ok, Konevo.DateTime.from_local_naive!(naive)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_local_datetime_value(<<date::binary-size(10), "T", time::binary-size(5)>>) do
    date <> "T" <> time <> ":00"
  end

  defp normalize_local_datetime_value(value), do: value

  defp value_for(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp preserve_refresh_token(%EmailIntegration{refresh_token: current}, attrs)
       when is_binary(current) and current != "" do
    case value_for(attrs, :refresh_token) do
      value when value in [nil, ""] ->
        attrs |> Map.delete(:refresh_token) |> Map.delete("refresh_token")

      _value ->
        attrs
    end
  end

  defp preserve_refresh_token(_integration, attrs), do: attrs

  defp blank_to_subject(nil), do: "(no subject)"

  defp blank_to_subject(subject) do
    case String.trim(to_string(subject)) do
      "" -> "(no subject)"
      value -> value
    end
  end

  defp build_rfc2822(from, recipients, subject, body, in_reply_to, attachments) do
    boundary = multipart_boundary()
    encoded_subject = "=?UTF-8?B?#{Base.encode64(subject)}?="

    lines =
      [
        "From: #{header_value(from)}",
        "To: #{header_list(recipients.to)}",
        "Subject: #{encoded_subject}",
        "MIME-Version: 1.0"
      ]
      |> maybe_header("Cc", recipients.cc)
      |> maybe_header("Bcc", recipients.bcc)
      |> then(fn l ->
        if in_reply_to,
          do:
            l ++
              [
                "In-Reply-To: #{header_value(in_reply_to)}",
                "References: #{header_value(in_reply_to)}"
              ],
          else: l
      end)
      |> content_headers(body, boundary, attachments)

    (Enum.join(lines, "\r\n") <> "\r\n\r\n" <> message_content(body, boundary, attachments))
    |> Base.url_encode64(padding: false)
  end

  defp maybe_header(lines, _name, []), do: lines
  defp maybe_header(lines, name, values), do: lines ++ ["#{name}: #{header_list(values)}"]

  defp content_headers(lines, body, _boundary, []),
    do:
      lines ++
        [
          "Content-Type: #{body_content_type(body)}; charset=utf-8",
          "Content-Transfer-Encoding: base64"
        ]

  defp content_headers(lines, _body, boundary, _attachments),
    do: lines ++ ["Content-Type: multipart/mixed; boundary=\"#{boundary}\""]

  defp message_content(body, _boundary, []), do: Base.encode64(body)

  defp message_content(body, boundary, attachments) do
    [
      body_part(body, boundary),
      Enum.map_join(attachments, "", &attachment_part(&1, boundary)),
      "--#{boundary}--\r\n"
    ]
    |> Enum.join("")
  end

  defp body_part(body, boundary) do
    [
      "--#{boundary}",
      "Content-Type: #{body_content_type(body)}; charset=utf-8",
      "Content-Transfer-Encoding: base64",
      "",
      Base.encode64(body),
      ""
    ]
    |> Enum.join("\r\n")
  end

  defp attachment_part(attachment, boundary) do
    filename = mime_param(attachment.filename)
    content_type = attachment.content_type || "application/octet-stream"

    [
      "--#{boundary}",
      "Content-Type: #{content_type}; name=\"#{filename}\"",
      "Content-Transfer-Encoding: base64",
      "Content-Disposition: attachment; filename=\"#{filename}\"",
      "",
      Base.encode64(attachment.bytes),
      ""
    ]
    |> Enum.join("\r\n")
  end

  defp body_content_type(body) do
    if html_body?(body), do: "text/html", else: "text/plain"
  end

  defp branded_body(body, %EmailIntegration{} = integration) do
    EmailBranding.apply(body, integration)
  end

  defp html_body(body) do
    if html_body?(body), do: body, else: nil
  end

  defp body_text(body) do
    body
    |> to_string()
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<\/p>/i, "\n\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> decode_text_entities()
    |> String.trim()
  end

  defp decode_text_entities(text) do
    text
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&#x27;", "'")
  end

  defp html_body?(body), do: is_binary(body) and String.match?(body, ~r/<[a-z][\s\S]*>/i)

  defp multipart_boundary do
    "konevo-#{Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)}"
  end

  defp header_list(values), do: values |> Enum.map_join(", ", &header_value/1)

  defp header_value(value) do
    value
    |> to_string()
    |> String.replace(["\r", "\n"], "")
  end

  defp mime_param(value) do
    value
    |> header_value()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
