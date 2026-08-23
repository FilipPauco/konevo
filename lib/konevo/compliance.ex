defmodule Konevo.Compliance do
  @moduledoc """
  The Compliance context — GDPR consent, suppression lists, and audit logging.

  ## Consent
  Tracks per-contact, per-channel opt-in/opt-out. Required before sending
  any marketing email or SMS. One record per (org, contact, channel) — upserted
  on change.

  ## Suppression
  A hard block list. Any value (email/phone) in the suppression list is never
  messaged regardless of consent. Populated by bounces, spam complaints, or
  manual entries. Check `suppressed?/3` before every send.

  ## Audit logs
  Append-only log of significant actions (who did what, when, on what).
  Called by other contexts and Oban workers — not exposed to end-users directly.
  """

  import Ecto.Query, warn: false

  alias Konevo.Accounts.Organization
  alias Konevo.Compliance.{AuditLog, Consent, SuppressionEntry}
  alias Konevo.Contacts.Contact
  alias Konevo.Repo

  # ---------------------------------------------------------------------------
  # Consent
  # ---------------------------------------------------------------------------

  @doc """
  Returns the consent record for a contact+channel, or nil.
  """
  def get_consent(%Contact{} = contact, channel) do
    Consent
    |> where(contact_id: ^contact.id, channel: ^channel)
    |> Repo.one()
  end

  @doc """
  Returns true if the contact has an active (granted) consent for the channel.
  """
  def has_consent?(%Contact{} = contact, channel) do
    Consent
    |> where(contact_id: ^contact.id, channel: ^channel, status: :granted)
    |> Repo.exists?()
  end

  @doc """
  Records (upserts) a granted consent for a contact+channel.

  - `source` — where the consent came from: `:manual`, `:import`, `:form`, `:api`
  - `ip_address` — optional; useful for web forms (GDPR audit trail)
  """
  def record_consent(%Contact{} = contact, channel, source, ip_address \\ nil) do
    case get_consent(contact, channel) do
      nil ->
        %Consent{organization_id: contact.organization_id, contact_id: contact.id}
        |> Consent.changeset(%{
          channel: channel,
          status: :granted,
          source: source,
          ip_address: ip_address,
          granted_at: DateTime.utc_now(:second)
        })
        |> Repo.insert()

      existing ->
        existing
        |> Consent.grant_changeset(source, ip_address)
        |> Repo.update()
    end
  end

  @doc """
  Revokes consent for a contact+channel. No-op if no consent record exists.
  """
  def revoke_consent(%Contact{} = contact, channel) do
    case get_consent(contact, channel) do
      nil ->
        {:ok, nil}

      existing ->
        existing
        |> Consent.revoke_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Returns all consent records for a contact, across all channels.
  """
  def list_consents(%Contact{} = contact) do
    Consent
    |> where(contact_id: ^contact.id)
    |> order_by([:channel])
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Suppression list
  # ---------------------------------------------------------------------------

  @doc """
  Returns true if the value (email/phone) is suppressed for the channel in the org.
  Always call this before sending any message.
  """
  def suppressed?(%Organization{} = org, channel, value) do
    SuppressionEntry
    |> where(organization_id: ^org.id, channel: ^channel, value: ^value)
    |> Repo.exists?()
  end

  @doc """
  Adds a value to the suppression list.

  - `reason` — `:unsubscribed`, `:bounced`, `:spam_complaint`, `:manual`
  - `source_message` — optional `MessageSent` that triggered the suppression
  """
  def suppress(%Organization{} = org, channel, value, reason, source_message \\ nil) do
    source_message_id = if source_message, do: source_message.id, else: nil

    %SuppressionEntry{organization_id: org.id, source_message_id: source_message_id}
    |> SuppressionEntry.changeset(%{channel: channel, value: value, reason: reason})
    |> Repo.insert()
  end

  @doc """
  Removes a suppression entry (e.g., after manual review / re-subscribe form).
  """
  def unsuppress(%Organization{} = org, channel, value) do
    SuppressionEntry
    |> where(organization_id: ^org.id, channel: ^channel, value: ^value)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Lists all suppression entries for an org, newest first.
  Accepts `channel:` filter option.
  """
  def list_suppressed(%Organization{} = org, opts \\ []) do
    channel = Keyword.get(opts, :channel)

    SuppressionEntry
    |> where(organization_id: ^org.id)
    |> maybe_filter_channel(channel)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Audit log
  # ---------------------------------------------------------------------------

  @doc """
  Records an audit log entry. Called by other contexts and workers.

  - `action` — dot-separated string: `"contact.created"`, `"deal.stage_changed"`
  - `actor` — the `%User{}` who performed the action, or nil for system actions
  - `opts` — keyword list:
    - `resource_type:` string (e.g., `"contact"`)
    - `resource_id:` integer
    - `metadata:` map with extra detail (old/new values, etc.)
    - `ip_address:` string
  """
  def log_action(%Organization{} = org, action, actor \\ nil, opts \\ []) do
    actor_id = if actor, do: actor.id, else: nil

    %AuditLog{organization_id: org.id, actor_id: actor_id}
    |> AuditLog.changeset(%{
      action: action,
      resource_type: Keyword.get(opts, :resource_type),
      resource_id: Keyword.get(opts, :resource_id),
      metadata: Keyword.get(opts, :metadata, %{}),
      ip_address: Keyword.get(opts, :ip_address)
    })
    |> Repo.insert()
  end

  @doc """
  Lists audit logs for an org, newest first.
  Accepts filter options:
    - `actor_id:` integer
    - `action:` string (exact match)
    - `resource_type:` string
    - `resource_id:` integer
    - `limit:` integer (default 100)
  """
  def list_audit_logs(%Organization{} = org, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    AuditLog
    |> where(organization_id: ^org.id)
    |> maybe_filter_actor(Keyword.get(opts, :actor_id))
    |> maybe_filter_action(Keyword.get(opts, :action))
    |> maybe_filter_resource(Keyword.get(opts, :resource_type), Keyword.get(opts, :resource_id))
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp maybe_filter_channel(query, nil), do: query
  defp maybe_filter_channel(query, channel), do: where(query, channel: ^channel)

  defp maybe_filter_actor(query, nil), do: query
  defp maybe_filter_actor(query, actor_id), do: where(query, actor_id: ^actor_id)

  defp maybe_filter_action(query, nil), do: query
  defp maybe_filter_action(query, action), do: where(query, action: ^action)

  defp maybe_filter_resource(query, nil, _), do: query

  defp maybe_filter_resource(query, type, nil),
    do: where(query, resource_type: ^type)

  defp maybe_filter_resource(query, type, id),
    do: where(query, resource_type: ^type, resource_id: ^id)

  @doc """
  Checks a contact has an address and is not suppressed before sending.
  """
  def check_deliverable(%Organization{} = org, %Contact{} = contact, channel) do
    value = sendable_value(contact, channel)

    cond do
      is_nil(value) -> {:error, :no_address}
      suppressed?(org, channel, value) -> {:error, :suppressed}
      true -> :ok
    end
  end

  @doc """
  Checks suppression AND consent for a contact before automated sending.
  Returns `:ok` if safe to send, `{:error, reason}` otherwise.
  """
  def check_sendable(%Organization{} = org, %Contact{} = contact, channel) do
    with :ok <- check_deliverable(org, contact, channel) do
      if has_consent?(contact, channel) do
        :ok
      else
        {:error, :no_consent}
      end
    end
  end

  defp sendable_value(%Contact{email: email}, :email), do: email
  defp sendable_value(%Contact{phone: phone}, :sms), do: phone

  @doc """
  Convenience: suppress a contact's primary value for a channel (e.g., on bounce).
  """
  def suppress_contact(%Organization{} = org, %Contact{} = contact, channel, reason, opts \\ []) do
    value = sendable_value(contact, channel)
    source_message = Keyword.get(opts, :source_message)

    if value do
      suppress(org, channel, value, reason, source_message)
    else
      {:error, :no_address}
    end
  end

  @doc """
  Revokes consent and suppresses the contact's value in one step (full unsubscribe).
  """
  def unsubscribe(%Organization{} = org, %Contact{} = contact, channel, opts \\ []) do
    source_message = Keyword.get(opts, :source_message)

    Repo.transaction(fn ->
      {:ok, _} = revoke_consent(contact, channel)
      suppress_contact(org, contact, channel, :unsubscribed, source_message: source_message)
    end)
  end
end
