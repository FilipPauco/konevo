defmodule Konevo.Uploads do
  @moduledoc """
  Tenant-scoped access to uploaded file records.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Konevo.Accounts
  alias Konevo.Accounts.Scope
  alias Konevo.Inbox.{Email, EmailThread}
  alias Konevo.Permissions
  alias Konevo.Repo
  alias Konevo.Uploads.UploadedFile
  alias Konevo.Uploads.UploadPath

  @per_page 10

  @doc """
  Returns a paginated uploaded-file list enriched with uploader and avatar data.
  """
  def list_uploaded_files(%Scope{} = scope, opts \\ []) do
    if authorized?(scope) do
      page = Keyword.get(opts, :page, 1)
      per_page = Keyword.get(opts, :per_page, @per_page)
      tenant_id = to_string(scope.org.id)
      query = from(file in visible_files_query(), where: file.tenant_id == ^tenant_id)
      total = Repo.aggregate(query, :count, :id)

      files =
        query
        |> order_by([file], desc: file.inserted_at, desc: file.id)
        |> limit(^per_page)
        |> offset(^((page - 1) * per_page))
        |> Repo.all()

      {:ok, {enrich_files(scope, tenant_id, files), total}}
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Returns the latest avatar for a tenant-owned resource.
  """
  def get_latest_avatar(%Scope{} = scope, owner_type, owner_id)
      when is_binary(owner_type) and is_binary(owner_id) do
    if authorized?(scope) do
      tenant_id = to_string(scope.org.id)

      avatar =
        Repo.one(
          from(file in visible_files_query(),
            where:
              file.tenant_id == ^tenant_id and file.context == :avatar and
                file.owner_type == ^owner_type and file.owner_id == ^owner_id,
            order_by: [desc: file.inserted_at, desc: file.id],
            limit: 1
          )
        )

      {:ok, avatar}
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Adds each contact's latest tenant-scoped avatar ID without N+1 queries.
  """
  def attach_contact_avatars(%Scope{} = scope, contacts) when is_list(contacts) do
    if authorized?(scope) do
      tenant_id = to_string(scope.org.id)
      owner_ids = Enum.map(contacts, &to_string(&1.id))
      avatars = latest_contact_avatars(tenant_id, owner_ids)

      contacts =
        Enum.map(contacts, fn contact ->
          avatar = Map.get(avatars, to_string(contact.id))
          %{contact | avatar_id: avatar && avatar.id}
        end)

      {:ok, contacts}
    else
      {:error, :unauthorized}
    end
  end

  defp authorized?(%Scope{user: user, org: org}) when not is_nil(user) and not is_nil(org) do
    not is_nil(Permissions.get_membership(user, org))
  end

  defp authorized?(_scope), do: false

  defp inbox_authorized?(%Scope{user: user, org: org})
       when not is_nil(user) and not is_nil(org) do
    Permissions.can?(user, org, :inbox, :read)
  end

  defp inbox_authorized?(_scope), do: false

  defp inbox_create_authorized?(%Scope{user: user, org: org})
       when not is_nil(user) and not is_nil(org) do
    Permissions.can?(user, org, :inbox, :create)
  end

  defp inbox_create_authorized?(_scope), do: false

  @doc """
  Returns files attached to a specific task (mixed_attachment context, owner_type "task").
  """
  def list_task_attachments(%Scope{} = scope, task_id) when is_integer(task_id) do
    if authorized?(scope) do
      tenant_id = to_string(scope.org.id)
      owner_id = to_string(task_id)

      files =
        from(f in visible_files_query(),
          where:
            f.tenant_id == ^tenant_id and
              f.context == :mixed_attachment and
              f.owner_type == "task" and
              f.owner_id == ^owner_id,
          order_by: [desc: f.inserted_at]
        )
        |> Repo.all()

      {:ok, files}
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Returns files attached to a specific email.
  """
  def list_email_attachments(%Scope{} = scope, email_id) when is_integer(email_id) do
    with true <- inbox_authorized?(scope),
         %Email{} <- Repo.get_by(Email, id: email_id, organization_id: scope.org.id) do
      {:ok, email_attachment_query(scope, [email_id]) |> Repo.all()}
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Returns all files attached to emails in a thread.
  """
  def list_thread_attachments(%Scope{} = scope, thread_id) when is_integer(thread_id) do
    with true <- inbox_authorized?(scope),
         %EmailThread{} <- Repo.get_by(EmailThread, id: thread_id, organization_id: scope.org.id) do
      email_ids =
        Email
        |> where(thread_id: ^thread_id, organization_id: ^scope.org.id)
        |> select([e], e.id)
        |> Repo.all()

      {:ok, email_attachment_query(scope, email_ids) |> Repo.all()}
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Returns files temporarily attached to an outbound email composer.
  """
  def list_email_draft_attachments(%Scope{} = scope, draft_owner_id)
      when is_binary(draft_owner_id) do
    if inbox_create_authorized?(scope) do
      {:ok, draft_attachment_query(scope, draft_owner_id) |> Repo.all()}
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Loads draft attachment bytes for MIME delivery.
  """
  def email_draft_attachments_for_delivery(%Scope{} = scope, draft_owner_id, file_ids)
      when is_binary(draft_owner_id) do
    with true <- inbox_create_authorized?(scope),
         {:ok, file_ids} <- normalize_file_ids(file_ids),
         {:ok, files} <- get_email_draft_attachments(scope, draft_owner_id, file_ids) do
      delivery_attachments(scope, files)
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc """
  Moves draft-owned attachments onto a sent email record.
  """
  def claim_email_draft_attachments(%Scope{} = scope, draft_owner_id, file_ids, %Email{} = email)
      when is_binary(draft_owner_id) do
    with true <- inbox_create_authorized?(scope),
         true <- email.organization_id == scope.org.id,
         {:ok, file_ids} <- normalize_file_ids(file_ids),
         {:ok, files} <- get_email_draft_attachments(scope, draft_owner_id, file_ids) do
      claim_draft_files(scope, draft_owner_id, file_ids, files, email)
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc """
  Deletes a draft attachment before the email is sent.
  """
  def delete_email_draft_attachment(%Scope{} = scope, file_id, draft_owner_id)
      when is_binary(draft_owner_id) do
    with true <- inbox_create_authorized?(scope),
         {file_id, ""} <- Integer.parse(to_string(file_id)),
         %UploadedFile{} = file <-
           Repo.get_by(draft_attachment_query(scope, draft_owner_id), id: file_id) do
      delete_uploaded_file(file)
    else
      false -> {:error, :unauthorized}
      nil -> {:error, :not_found}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Deletes a task attachment record and its storage file.
  """
  def delete_task_attachment(%Scope{} = scope, file_id) do
    if authorized?(scope) do
      tenant_id = to_string(scope.org.id)

      case Repo.get_by(visible_files_query(),
             id: file_id,
             tenant_id: tenant_id,
             owner_type: "task"
           ) do
        nil ->
          {:error, :not_found}

        file ->
          delete_uploaded_file(file)
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Retries physical deletion for uploaded files that were logically deleted.
  """
  def cleanup_deleted_files(limit \\ 100) when is_integer(limit) and limit > 0 do
    files =
      UploadedFile
      |> where([file], not is_nil(file.deleted_at))
      |> order_by([file], asc: file.delete_failed_at, asc: file.deleted_at)
      |> limit(^limit)
      |> Repo.all()

    results = Enum.map(files, &retry_deleted_file/1)

    {:ok,
     %{
       deleted: Enum.count(results, &match?({:ok, _}, &1)),
       failed: Enum.count(results, &match?({:error, _}, &1))
     }}
  end

  defp delete_uploaded_file(%UploadedFile{} = file) do
    with {:ok, pending_file} <- mark_pending_delete(file),
         {:error, reason} <- finalize_deleted_file(pending_file),
         {:ok, failed_file} <- mark_delete_failed(pending_file, reason) do
      Logger.warning("[Uploads] Attachment file delete queued for retry: #{inspect(reason)}")
      {:ok, failed_file}
    else
      {:ok, deleted_file} -> {:ok, deleted_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp retry_deleted_file(%UploadedFile{} = file) do
    with {:error, reason} <- finalize_deleted_file(file),
         {:ok, _failed_file} <- mark_delete_failed(file, reason) do
      {:error, reason}
    else
      {:ok, deleted_file} -> {:ok, deleted_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp mark_pending_delete(%UploadedFile{} = file) do
    file
    |> Ecto.Changeset.change(%{
      deleted_at: DateTime.utc_now(:second),
      delete_failed_at: nil,
      delete_error: nil
    })
    |> Repo.update()
  end

  defp finalize_deleted_file(%UploadedFile{} = file) do
    storage_path = UploadPath.expand(file.storage_path)

    with :ok <- remove_storage_file(storage_path) do
      Repo.delete(file)
    end
  rescue
    _error -> {:error, :invalid_storage_path}
  end

  defp mark_delete_failed(%UploadedFile{} = file, reason) do
    file
    |> Ecto.Changeset.change(%{
      delete_failed_at: DateTime.utc_now(:second),
      delete_error: inspect(reason)
    })
    |> Repo.update()
  end

  defp remove_storage_file(storage_path) do
    case File.rm(storage_path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp visible_files_query do
    from(file in UploadedFile, where: is_nil(file.deleted_at))
  end

  defp email_attachment_query(scope, email_ids) do
    owner_ids = Enum.map(email_ids, &to_string/1)
    tenant_id = to_string(scope.org.id)

    from(f in visible_files_query(),
      where:
        f.tenant_id == ^tenant_id and
          f.context == :mixed_attachment and
          f.owner_type == "email" and
          f.owner_id in ^owner_ids,
      order_by: [desc: f.inserted_at, desc: f.id]
    )
  end

  defp draft_attachment_query(scope, draft_owner_id) do
    tenant_id = to_string(scope.org.id)

    from(f in visible_files_query(),
      where:
        f.tenant_id == ^tenant_id and
          f.context == :mixed_attachment and
          f.owner_type == "email_draft" and
          f.owner_id == ^draft_owner_id,
      order_by: [desc: f.inserted_at, desc: f.id]
    )
  end

  defp get_email_draft_attachments(_scope, _draft_owner_id, []), do: {:ok, []}

  defp get_email_draft_attachments(scope, draft_owner_id, file_ids) do
    files =
      draft_attachment_query(scope, draft_owner_id)
      |> where([f], f.id in ^file_ids)
      |> Repo.all()

    if length(files) == length(file_ids) do
      {:ok, files}
    else
      {:error, :not_found}
    end
  end

  defp delivery_attachments(scope, files) do
    files
    |> Enum.reduce_while({:ok, []}, &collect_delivery_attachment(scope, &1, &2))
    |> normalize_delivery_attachments()
  end

  defp collect_delivery_attachment(scope, file, {:ok, attachments}) do
    case delivery_attachment(scope, file) do
      {:ok, attachment} -> {:cont, {:ok, [attachment | attachments]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp normalize_delivery_attachments({:ok, attachments}), do: {:ok, Enum.reverse(attachments)}
  defp normalize_delivery_attachments(error), do: error

  defp delivery_attachment(scope, %UploadedFile{} = file) do
    with {:ok, path} <- UploadPath.resolve_for_serving(file.storage_path, to_string(scope.org.id)),
         {:ok, bytes} <- File.read(path) do
      {:ok,
       %{
         id: file.id,
         filename: file.original_filename,
         content_type: file.content_type,
         bytes: bytes
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp claim_draft_files(_scope, _draft_owner_id, [], _files, _email), do: {:ok, []}

  defp claim_draft_files(scope, draft_owner_id, file_ids, files, email) do
    tenant_id = to_string(scope.org.id)
    owner_id = to_string(email.id)

    Repo.transaction(fn ->
      {count, _} =
        draft_attachment_query(scope, draft_owner_id)
        |> where([f], f.id in ^file_ids)
        |> exclude(:order_by)
        |> Repo.update_all(set: [owner_type: "email", owner_id: owner_id])

      if count != length(file_ids) do
        Repo.rollback(:not_found)
      end

      Repo.update_all(
        from(e in Email, where: e.id == ^email.id and e.organization_id == ^scope.org.id),
        set: [has_attachments: true]
      )

      Repo.update_all(
        from(t in EmailThread,
          where:
            t.id == ^email.thread_id and
              t.organization_id == ^scope.org.id and
              t.has_attachments == false
        ),
        set: [has_attachments: true]
      )

      Enum.map(files, &%{&1 | owner_type: "email", owner_id: owner_id, tenant_id: tenant_id})
    end)
  end

  defp normalize_file_ids(nil), do: {:ok, []}
  defp normalize_file_ids([]), do: {:ok, []}

  defp normalize_file_ids(file_ids) when is_list(file_ids) do
    file_ids
    |> Enum.reduce_while({:ok, []}, fn file_id, {:ok, acc} ->
      case normalize_file_id(file_id) do
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        :error -> {:halt, {:error, :invalid_file_id}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, ids |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  defp normalize_file_ids(file_id), do: normalize_file_ids([file_id])

  defp normalize_file_id(file_id) when is_integer(file_id) and file_id > 0, do: {:ok, file_id}

  defp normalize_file_id(file_id) do
    case Integer.parse(to_string(file_id)) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> :error
    end
  end

  defp enrich_files(scope, tenant_id, files) do
    owner_ids = user_owner_ids(files)

    users_by_id =
      scope
      |> Accounts.list_organization_users_by_ids(parse_integer_ids(owner_ids))
      |> Map.new(&{to_string(&1.id), &1})

    avatars_by_owner = latest_avatars(tenant_id, owner_ids)

    Enum.map(files, fn file ->
      %{
        id: file.id,
        file: file,
        author: Map.get(users_by_id, file.owner_id),
        avatar: Map.get(avatars_by_owner, file.owner_id)
      }
    end)
  end

  defp user_owner_ids(files) do
    files
    |> Enum.filter(&(&1.owner_type == "user"))
    |> Enum.map(& &1.owner_id)
    |> Enum.uniq()
  end

  defp parse_integer_ids(ids) do
    Enum.flat_map(ids, fn id ->
      case Integer.parse(id) do
        {integer, ""} -> [integer]
        _invalid -> []
      end
    end)
  end

  defp latest_avatars(_tenant_id, []), do: %{}

  defp latest_avatars(tenant_id, owner_ids) do
    Repo.all(
      from(file in visible_files_query(),
        where:
          file.tenant_id == ^tenant_id and file.context == :avatar and
            file.owner_type == "user" and file.owner_id in ^owner_ids,
        order_by: [desc: file.inserted_at, desc: file.id]
      )
    )
    |> Enum.reduce(%{}, fn avatar, avatars ->
      Map.put_new(avatars, avatar.owner_id, avatar)
    end)
  end

  defp latest_contact_avatars(_tenant_id, []), do: %{}

  defp latest_contact_avatars(tenant_id, owner_ids) do
    Repo.all(
      from(file in visible_files_query(),
        where:
          file.tenant_id == ^tenant_id and file.context == :avatar and
            file.owner_type == "contact" and file.owner_id in ^owner_ids,
        order_by: [desc: file.inserted_at, desc: file.id]
      )
    )
    |> Enum.reduce(%{}, fn avatar, avatars ->
      Map.put_new(avatars, avatar.owner_id, avatar)
    end)
  end
end
