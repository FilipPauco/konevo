defmodule Konevo.Inbox.GmailImporter do
  @moduledoc false

  require Logger

  import Ecto.Query, warn: false

  alias Konevo.AI
  alias Konevo.Automation
  alias Konevo.Contacts.Contact
  alias Konevo.Inbox.{Email, EmailIntegration, EmailThread, GmailClient}
  alias Konevo.Repo
  alias Konevo.Uploads.UploadedFile
  alias Konevo.Uploads.UploadProcessor
  alias Konevo.Workers.{EmailReplyDraftWorker, EmailTaskExtractionWorker, NoReplyFollowUpWorker}

  @page_size 100

  def sync_recent(%EmailIntegration{} = integration) do
    import_queries(integration, ["in:inbox newer_than:180d", "in:sent newer_than:180d"],
      max_pages: 1
    )
  end

  def import_history(%EmailIntegration{} = integration, query) when is_binary(query) do
    import_queries(integration, [query], max_pages: :all)
  end

  def import_queries(%EmailIntegration{} = integration, queries, opts) when is_list(queries) do
    with {:ok, access_token} <- ensure_valid_token(integration),
         {:ok, thread_refs} <- list_thread_refs(access_token, queries, opts) do
      result =
        thread_refs
        |> Task.async_stream(&fetch_and_upsert_thread(&1, access_token, integration),
          max_concurrency: 5,
          timeout: :infinity
        )
        |> Enum.reduce(%{imported: 0, processed: 0}, &count_import_result/2)

      Repo.update_all(
        from(i in EmailIntegration, where: i.id == ^integration.id),
        set: [last_sync_at: DateTime.utc_now(:second)]
      )

      {:ok, result}
    end
  end

  defp list_thread_refs(access_token, queries, opts) do
    max_pages = Keyword.get(opts, :max_pages, :all)

    queries
    |> Enum.reduce_while({:ok, []}, fn query, {:ok, acc} ->
      case list_query_thread_refs(access_token, query, nil, 1, max_pages, []) do
        {:ok, refs} -> {:cont, {:ok, acc ++ refs}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, refs} -> {:ok, Enum.uniq_by(refs, & &1["id"])}
      error -> error
    end
  end

  defp list_query_thread_refs(_access_token, _query, _page_token, page, max_pages, acc)
       when is_integer(max_pages) and page > max_pages do
    {:ok, acc}
  end

  defp list_query_thread_refs(access_token, query, page_token, page, max_pages, acc) do
    case GmailClient.list_threads(access_token,
           q: query,
           max_results: @page_size,
           page_token: page_token
         ) do
      {:ok, %{"threads" => refs, "nextPageToken" => next_page_token}} ->
        list_query_thread_refs(
          access_token,
          query,
          next_page_token,
          page + 1,
          max_pages,
          acc ++ refs
        )

      {:ok, %{"threads" => refs}} ->
        {:ok, acc ++ refs}

      {:ok, _body} ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_and_upsert_thread(%{"id" => thread_id}, access_token, integration) do
    case GmailClient.get_thread(access_token, thread_id) do
      {:ok, thread_data} ->
        attrs = parse_thread(thread_data)

        case upsert_thread(integration.organization_id, attrs) do
          {:ok, thread_record, status} ->
            messages = Map.get(thread_data, "messages") || []

            messages
            |> sort_messages()
            |> Enum.each(&store_message(&1, thread_record, integration, access_token))

            {:ok, status}

          {:error, reason} ->
            Logger.warning(
              "Gmail import: failed to upsert thread #{thread_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning("Gmail import: failed to fetch thread #{thread_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp count_import_result({:ok, {:ok, :created}}, counts) do
    %{counts | imported: counts.imported + 1, processed: counts.processed + 1}
  end

  defp count_import_result({:ok, {:ok, :updated}}, counts) do
    %{counts | processed: counts.processed + 1}
  end

  defp count_import_result(_result, counts), do: counts

  defp upsert_thread(org_id, attrs) do
    case Repo.get_by(EmailThread,
           organization_id: org_id,
           thread_id_gmail: attrs.thread_id_gmail
         ) do
      nil ->
        %EmailThread{organization_id: org_id}
        |> EmailThread.changeset(attrs)
        |> Repo.insert(on_conflict: :nothing)
        |> case do
          {:ok, %EmailThread{id: nil}} ->
            {:ok,
             Repo.get_by!(EmailThread,
               organization_id: org_id,
               thread_id_gmail: attrs.thread_id_gmail
             ), :updated}

          {:ok, thread} ->
            {:ok, thread, :created}

          error ->
            error
        end

      existing ->
        existing
        |> EmailThread.changeset(provider_thread_attrs(attrs))
        |> Repo.update()
        |> case do
          {:ok, thread} -> {:ok, thread, :updated}
          error -> error
        end
    end
  end

  defp provider_thread_attrs(attrs) do
    Map.drop(attrs, [:is_unresolved, :is_archived, :is_favorite, :trashed_at])
  end

  defp parse_thread(%{"id" => thread_id, "messages" => messages} = thread) do
    messages = sort_messages(messages)

    first_msg = List.first(messages) || %{}
    last_msg = List.last(messages) || %{}
    first_headers = get_in(first_msg, ["payload", "headers"]) || []
    subject = get_header(first_headers, "Subject") || "(no subject)"
    snippet = Map.get(last_msg, "snippet") || Map.get(thread, "snippet") || ""
    last_date = parse_internal_date(last_msg["internalDate"])

    inbound_dates =
      messages
      |> Enum.reject(&sent_message?/1)
      |> Enum.map(&parse_internal_date(&1["internalDate"]))

    outbound_dates =
      messages
      |> Enum.filter(&sent_message?/1)
      |> Enum.map(&parse_internal_date(&1["internalDate"]))

    last_inbound_at = latest_datetime(inbound_dates)
    last_outbound_at = latest_datetime(outbound_dates)
    has_inbound? = not is_nil(last_inbound_at)
    unread? = Enum.any?(messages, &unread_message?/1)

    %{
      thread_id_gmail: thread_id,
      subject: subject,
      snippet: truncate(snippet, 250),
      participants: thread_participants(messages),
      last_activity_at: last_date,
      last_inbound_at: last_inbound_at,
      last_outbound_at: last_outbound_at,
      is_unresolved: has_inbound?,
      read_at: if(unread?, do: nil, else: last_date),
      has_attachments: Enum.any?(messages, &message_has_attachments?/1)
    }
  end

  defp parse_thread(%{"id" => thread_id} = thread) do
    now = DateTime.utc_now(:second)

    %{
      thread_id_gmail: thread_id,
      subject: "(no subject)",
      snippet: Map.get(thread, "snippet", "") |> truncate(250),
      participants: [],
      last_activity_at: now,
      last_inbound_at: now,
      is_unresolved: true
    }
  end

  defp sort_messages(messages) do
    Enum.sort_by(messages, &String.to_integer(&1["internalDate"] || "0"))
  end

  defp thread_participants(messages) do
    messages
    |> Enum.reverse()
    |> Enum.map(&get_header(get_in(&1, ["payload", "headers"]) || [], "From"))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp ensure_valid_token(%EmailIntegration{} = integration) do
    if token_expired?(integration) do
      refresh_token(integration)
    else
      {:ok, integration.access_token}
    end
  end

  defp refresh_token(%EmailIntegration{} = integration) do
    case GmailClient.refresh_access_token(integration.refresh_token) do
      {:ok, %{"access_token" => new_token, "expires_in" => expires_in}} ->
        expires_at = DateTime.add(DateTime.utc_now(:second), expires_in, :second)

        Repo.update_all(
          from(i in EmailIntegration, where: i.id == ^integration.id),
          set: [access_token: new_token, token_expires_at: expires_at]
        )

        {:ok, new_token}

      {:error, reason} ->
        if GmailClient.invalid_grant?(reason) do
          disable_sync(integration)
          {:error, :gmail_reauthorization_required}
        else
          {:error, {:token_refresh_failed, reason}}
        end
    end
  end

  defp disable_sync(%EmailIntegration{} = integration) do
    Repo.update_all(
      from(i in EmailIntegration, where: i.id == ^integration.id),
      set: [sync_enabled: false]
    )

    :ok
  end

  defp token_expired?(%EmailIntegration{token_expires_at: nil}), do: true

  defp token_expired?(%EmailIntegration{token_expires_at: expires_at}) do
    buffer = DateTime.add(DateTime.utc_now(:second), 5 * 60, :second)
    DateTime.compare(expires_at, buffer) == :lt
  end

  defp store_message(msg, %EmailThread{} = thread, integration, access_token) do
    attrs = parse_message(msg, integration.email_address)

    email =
      case Repo.get_by(Email, message_id: attrs.message_id) do
        %Email{} = existing ->
          update_existing_email_attachment_state(existing, attrs)

        nil ->
          insert_email(thread, attrs)
      end

    if email do
      maybe_link_inbound_thread_to_contact(email, integration.organization_id)
      maybe_enqueue_email_task_extraction(email, integration)
      maybe_enqueue_email_reply_draft(email, integration)
      maybe_enqueue_no_reply_follow_up(email, integration)
      store_message_attachments(msg, email, access_token)
      update_thread_attachment_state(thread, email.has_attachments)
    end

    :ok
  end

  defp maybe_enqueue_email_task_extraction(%Email{is_inbound: true} = email, integration) do
    if AI.latest_extraction(email) do
      :ok
    else
      enqueue_email_task_extraction(email, integration)
    end
  end

  defp maybe_enqueue_email_task_extraction(_email, _integration), do: :ok

  defp maybe_enqueue_email_reply_draft(%Email{is_inbound: true} = email, integration) do
    %{
      "email_id" => email.id,
      "organization_id" => integration.organization_id,
      "user_id" => integration.user_id
    }
    |> EmailReplyDraftWorker.new(
      unique: [period: 86_400, fields: [:worker, :args], keys: [:email_id]]
    )
    |> then(&Oban.insert(Konevo.Oban, &1))
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Gmail import: failed to enqueue AI reply draft for email #{email.id}: #{inspect(reason)}"
        )
    end
  end

  defp maybe_enqueue_email_reply_draft(_email, _integration), do: :ok

  defp maybe_enqueue_no_reply_follow_up(%Email{}, integration) do
    case NoReplyFollowUpWorker.enqueue(integration.organization_id) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Gmail import: failed to enqueue no-reply follow-up: #{inspect(reason)}")
    end
  end

  defp maybe_link_inbound_thread_to_contact(%Email{is_inbound: true} = email, organization_id) do
    with address when is_binary(address) <- normalize_address(email.from),
         %Contact{} = contact <- contact_for_email(organization_id, address) do
      Repo.update_all(
        from(thread in EmailThread,
          where:
            thread.id == ^email.thread_id and thread.organization_id == ^organization_id and
              is_nil(thread.contact_id)
        ),
        set: [contact_id: contact.id]
      )
    end

    :ok
  end

  defp maybe_link_inbound_thread_to_contact(_email, _organization_id), do: :ok

  defp contact_for_email(organization_id, address) do
    Contact
    |> where(organization_id: ^organization_id)
    |> where([contact], fragment("lower(?)", contact.email) == ^address)
    |> Repo.one()
  end

  defp normalize_address(address) when is_binary(address) do
    address
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_address(_address), do: nil

  defp enqueue_email_task_extraction(email, integration) do
    changeset =
      %{
        "email_id" => email.id,
        "organization_id" => integration.organization_id,
        "user_id" => integration.user_id
      }
      |> EmailTaskExtractionWorker.new(
        unique: [
          period: 86_400,
          fields: [:worker, :args],
          keys: [:email_id]
        ]
      )

    case Oban.insert(Konevo.Oban, changeset) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Gmail import: failed to enqueue email task extraction for email #{email.id}: #{inspect(reason)}"
        )

        :ok
    end
  rescue
    error ->
      Logger.warning(
        "Gmail import: failed to enqueue email task extraction for email #{email.id}: #{Exception.message(error)}"
      )

      :ok
  end

  defp insert_email(thread, attrs) do
    %Email{organization_id: thread.organization_id, thread_id: thread.id}
    |> Email.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
    |> case do
      {:ok, %Email{id: nil}} ->
        Repo.get_by(Email, message_id: attrs.message_id)

      {:ok, email} ->
        update_thread_after_imported_email(thread, email)
        email

      {:error, changeset} ->
        Logger.warning(
          "Gmail import: failed to store message #{attrs.message_id}: #{inspect(changeset.errors)}"
        )

        nil
    end
  end

  defp parse_message(msg, integration_email) do
    headers = get_in(msg, ["payload", "headers"]) || []
    label_ids = msg["labelIds"] || []
    {text_body, html_body} = extract_bodies(msg["payload"])

    %{
      message_id: get_header(headers, "Message-ID") || msg["id"],
      from: get_header(headers, "From") |> extract_email() || integration_email,
      to: get_header(headers, "To") |> split_addresses(),
      cc: get_header(headers, "Cc") |> split_addresses(),
      bcc: [],
      subject: get_header(headers, "Subject") || "(no subject)",
      body: text_body,
      html_body: html_body,
      headers: headers_to_map(headers),
      inline_image_cids: inline_image_cids(msg["payload"]),
      received_at: parse_internal_date(msg["internalDate"]),
      is_inbound: "SENT" not in label_ids,
      has_attachments: msg |> Map.get("payload") |> attachment_refs() |> Enum.any?()
    }
  end

  defp update_existing_email_attachment_state(%Email{} = email, attrs) do
    changes =
      %{}
      |> maybe_mark_has_attachments(email, attrs)
      |> maybe_add_inline_image_cids(email, attrs)

    if changes == %{} do
      email
    else
      email
      |> Email.changeset(changes)
      |> Repo.update!()
    end
  end

  defp maybe_mark_has_attachments(changes, email, attrs) do
    if attrs.has_attachments and not email.has_attachments,
      do: Map.put(changes, :has_attachments, true),
      else: changes
  end

  defp maybe_add_inline_image_cids(changes, email, attrs) do
    cids = attrs.inline_image_cids

    if cids != %{} and email.inline_image_cids != cids,
      do: Map.put(changes, :inline_image_cids, cids),
      else: changes
  end

  defp update_thread_attachment_state(%EmailThread{} = thread, true) do
    Repo.update_all(
      from(t in EmailThread, where: t.id == ^thread.id and t.has_attachments == false),
      set: [has_attachments: true]
    )
  end

  defp update_thread_attachment_state(_thread, _has_attachments), do: :ok

  defp update_thread_after_imported_email(
         %EmailThread{} = thread,
         %Email{is_inbound: true} = email
       ) do
    updated =
      thread
      |> EmailThread.changeset(%{
        read_at: nil,
        is_unresolved: true,
        is_archived: false,
        trashed_at: nil,
        snippet: email_snippet(email),
        participants: latest_participants(thread, email),
        last_inbound_at: email.received_at,
        last_activity_at: email.received_at,
        has_attachments: thread.has_attachments or email.has_attachments
      })
      |> Repo.update!()

    {:ok, _count} =
      Automation.cancel_active_executions_for_contact_id(
        updated.organization_id,
        updated.contact_id
      )

    updated
  end

  defp update_thread_after_imported_email(%EmailThread{} = thread, %Email{} = email) do
    thread
    |> EmailThread.changeset(%{
      is_unresolved: false,
      read_at: DateTime.utc_now(:second),
      snippet: email_snippet(email),
      participants: latest_participants(thread, email),
      last_outbound_at: email.received_at,
      last_activity_at: email.received_at,
      has_attachments: thread.has_attachments or email.has_attachments
    })
    |> Repo.update!()
  end

  defp email_snippet(%Email{} = email) do
    [email.body, email.html_body, email.subject]
    |> Enum.find_value(&snippet_text/1)
    |> case do
      nil -> ""
      snippet -> truncate(snippet, 250)
    end
  end

  defp snippet_text(nil), do: nil

  defp snippet_text(value) do
    value =
      value
      |> to_string()
      |> String.replace(~r/<br\s*\/?>/i, " ")
      |> String.replace(~r/<\/p>/i, " ")
      |> String.replace(~r/<[^>]+>/, "")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    if value == "", do: nil, else: value
  end

  defp latest_participants(%EmailThread{} = thread, %Email{} = email) do
    [email.from | thread.participants || []]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp store_message_attachments(msg, %Email{} = email, access_token) do
    msg
    |> Map.get("payload")
    |> attachment_refs()
    |> Enum.each(&store_message_attachment(&1, msg["id"], email, access_token))
  end

  defp store_message_attachment(ref, gmail_message_id, %Email{} = email, access_token) do
    with false <- attachment_stored?(email, ref.filename),
         {:ok, bytes} <- attachment_bytes(ref, gmail_message_id, access_token),
         {:ok, temp_path} <- write_temp_attachment(ref.filename, bytes) do
      case UploadProcessor.process(
             temp_path,
             :mixed_attachment,
             to_string(email.organization_id),
             to_string(email.id),
             "email",
             ref.filename
           ) do
        {:ok, _file} ->
          :ok

        {:error, reason} ->
          File.rm(temp_path)

          Logger.warning(
            "Gmail import: failed to store attachment #{ref.filename}: #{inspect(reason)}"
          )
      end
    else
      true ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Gmail import: failed to fetch attachment #{ref.filename}: #{inspect(reason)}"
        )
    end
  end

  defp attachment_stored?(%Email{} = email, filename) do
    owner_id = to_string(email.id)

    UploadedFile
    |> where(
      owner_type: "email",
      owner_id: ^owner_id,
      original_filename: ^filename
    )
    |> Repo.exists?()
  end

  defp attachment_bytes(%{data: data}, _gmail_message_id, _access_token) when is_binary(data) do
    decode_attachment_data(data)
  end

  defp attachment_bytes(%{attachment_id: attachment_id}, gmail_message_id, access_token)
       when is_binary(attachment_id) do
    with {:ok, %{"data" => data}} <-
           GmailClient.get_attachment(access_token, gmail_message_id, attachment_id) do
      decode_attachment_data(data)
    end
  end

  defp attachment_bytes(_ref, _gmail_message_id, _access_token), do: {:error, :missing_data}

  defp attachment_refs(nil), do: []

  defp attachment_refs(%{"parts" => parts} = payload) when is_list(parts) do
    own_attachment_refs(payload) ++ Enum.flat_map(parts, &attachment_refs/1)
  end

  defp attachment_refs(payload), do: own_attachment_refs(payload)

  defp own_attachment_refs(%{"filename" => filename, "body" => body})
       when is_binary(filename) and filename != "" and is_map(body) do
    [%{filename: filename, attachment_id: body["attachmentId"], data: body["data"]}]
  end

  defp own_attachment_refs(_payload), do: []

  defp inline_image_cids(nil), do: %{}

  defp inline_image_cids(%{"parts" => parts} = payload) when is_list(parts) do
    Enum.reduce(parts, own_inline_image_cids(payload), fn part, cids ->
      Map.merge(cids, inline_image_cids(part))
    end)
  end

  defp inline_image_cids(payload), do: own_inline_image_cids(payload)

  defp own_inline_image_cids(%{"filename" => filename, "headers" => headers})
       when is_binary(filename) and filename != "" and is_list(headers) do
    case get_header(headers, "Content-ID") |> normalize_content_id() do
      nil -> %{}
      content_id -> %{content_id => filename}
    end
  end

  defp own_inline_image_cids(_payload), do: %{}

  defp normalize_content_id(nil), do: nil

  defp normalize_content_id(content_id) do
    content_id
    |> String.trim()
    |> String.trim_leading("<")
    |> String.trim_trailing(">")
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp extract_bodies(payload) do
    {find_body_part(payload, "text/plain"), find_body_part(payload, "text/html")}
  end

  defp find_body_part(nil, _target), do: nil

  defp find_body_part(%{"mimeType" => mime, "body" => %{"data" => data}}, target)
       when mime == target and is_binary(data) and byte_size(data) > 0 do
    safe_decode64(data)
  end

  defp find_body_part(%{"parts" => parts}, target) when is_list(parts) do
    Enum.find_value(parts, &find_body_part(&1, target))
  end

  defp find_body_part(_payload, _target), do: nil

  defp get_header(headers, name) when is_list(headers) do
    case Enum.find(headers, &(&1["name"] == name)) do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp get_header(_headers, _name), do: nil

  defp headers_to_map(headers), do: Map.new(headers, &{&1["name"], &1["value"]})

  defp latest_datetime([]), do: nil
  defp latest_datetime(dates), do: Enum.max_by(dates, &DateTime.to_unix/1)

  defp sent_message?(msg), do: "SENT" in (msg["labelIds"] || [])

  defp unread_message?(msg), do: "UNREAD" in (msg["labelIds"] || [])

  defp message_has_attachments?(msg) do
    msg
    |> Map.get("payload")
    |> attachment_refs()
    |> Enum.any?()
  end

  defp parse_internal_date(nil), do: DateTime.utc_now(:second)

  defp parse_internal_date(ts) when is_binary(ts),
    do: ts |> String.to_integer() |> parse_internal_date()

  defp parse_internal_date(ts) when is_integer(ts), do: DateTime.from_unix!(div(ts, 1000))

  defp truncate(str, max) do
    if String.length(str) > max, do: String.slice(str, 0, max), else: str
  end

  defp safe_decode64(data) do
    case Base.url_decode64(data, padding: false) do
      {:ok, decoded} -> decoded
      :error -> safe_decode64_padded(data)
    end
  end

  defp safe_decode64_padded(data) do
    case Base.url_decode64(data, padding: true) do
      {:ok, decoded} -> decoded
      :error -> nil
    end
  end

  defp decode_attachment_data(data) do
    case safe_decode64(data) do
      nil -> {:error, :decode_failed}
      bytes -> {:ok, bytes}
    end
  end

  defp write_temp_attachment(filename, bytes) do
    temp_path = Path.join(System.tmp_dir!(), "konevo-email-#{Ecto.UUID.generate()}-#{filename}")

    case File.write(temp_path, bytes) do
      :ok -> {:ok, temp_path}
      {:error, reason} -> {:error, {:temp_write_failed, reason}}
    end
  end

  defp extract_email(nil), do: nil

  defp extract_email(addr) do
    case Regex.run(~r/<([^>@\s]+@[^>]+)>/, addr) do
      [_, email] -> String.trim(email)
      nil -> String.trim(addr)
    end
  end

  defp split_addresses(nil), do: []

  defp split_addresses(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&extract_email/1)
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
  end
end
