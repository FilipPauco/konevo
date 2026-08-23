defmodule Konevo.UploadsTest do
  use Konevo.DataCase, async: false

  import Konevo.Factory

  alias Konevo.Accounts.Scope
  alias Konevo.Inbox.{Email, EmailThread}
  alias Konevo.Repo
  alias Konevo.Uploads
  alias Konevo.Uploads.UploadedFile

  setup do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org)
    scope = Scope.for_user_in_org(user, org, membership)
    %{user: user, org: org, scope: scope}
  end

  test "lists tenant files with their author and latest avatar", %{
    user: user,
    org: org,
    scope: scope
  } do
    avatar = insert_file(org, user, %{context: :avatar, original_filename: "avatar.jpg"})
    document = insert_file(org, user, %{original_filename: "proposal.pdf"})

    assert {:ok, {rows, 2}} = Uploads.list_uploaded_files(scope)
    row = Enum.find(rows, &(&1.file.id == document.id))

    assert row.author.id == user.id
    assert row.avatar.id == avatar.id
  end

  test "keeps files tenant scoped and paginated", %{user: user, org: org, scope: scope} do
    insert_file(org, user, %{original_filename: "one.pdf"})
    insert_file(org, user, %{original_filename: "two.pdf"})

    other_user = insert(:user)
    other_org = insert(:organization)
    insert(:membership, user: other_user, organization: other_org)
    insert_file(other_org, other_user, %{original_filename: "secret.pdf"})

    assert {:ok, {[row], 2}} = Uploads.list_uploaded_files(scope, page: 2, per_page: 1)
    assert row.file.tenant_id == to_string(org.id)
  end

  test "returns the latest contact avatar from the current tenant", %{
    user: user,
    org: org,
    scope: scope
  } do
    older =
      insert_file(org, user, %{
        context: :avatar,
        owner_type: "contact",
        owner_id: "42",
        original_filename: "older.jpg"
      })

    newer =
      insert_file(org, user, %{
        context: :avatar,
        owner_type: "contact",
        owner_id: "42",
        original_filename: "newer.jpg"
      })

    assert older.id < newer.id
    assert {:ok, avatar} = Uploads.get_latest_avatar(scope, "contact", "42")
    assert avatar.id == newer.id
  end

  test "does not return a contact avatar from another tenant", %{scope: scope} do
    other_user = insert(:user)
    other_org = insert(:organization)
    insert(:membership, user: other_user, organization: other_org)

    insert_file(other_org, other_user, %{
      context: :avatar,
      owner_type: "contact",
      owner_id: "42",
      original_filename: "secret.jpg"
    })

    assert {:ok, nil} = Uploads.get_latest_avatar(scope, "contact", "42")
  end

  test "attaches latest contact avatars in one tenant-scoped pass", %{
    user: user,
    org: org,
    scope: scope
  } do
    contact = insert(:contact, user: user, organization: org)

    avatar =
      insert_file(org, user, %{
        context: :avatar,
        owner_type: "contact",
        owner_id: to_string(contact.id),
        original_filename: "contact.jpg"
      })

    assert {:ok, [contact]} = Uploads.attach_contact_avatars(scope, [contact])
    assert contact.avatar_id == avatar.id
  end

  test "deletes task attachment record and storage file", %{org: org, scope: scope} do
    uploads_root =
      Path.join(System.tmp_dir!(), "uploads-delete-#{System.unique_integer([:positive])}")

    previous_root = Application.get_env(:konevo, :uploads_root)
    Application.put_env(:konevo, :uploads_root, uploads_root)

    on_exit(fn ->
      restore_env(:konevo, :uploads_root, previous_root)
      File.rm_rf!(uploads_root)
    end)

    task = insert(:task, organization: org, created_by: scope.user)
    storage_path = "attachments/#{org.id}/#{task.id}/file.pdf"
    full_path = Path.join(uploads_root, storage_path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, "%PDF-1.7\n")

    file =
      insert_file(org, scope.user, %{
        context: :mixed_attachment,
        owner_type: "task",
        owner_id: to_string(task.id),
        storage_path: storage_path
      })

    assert {:ok, _file} = Uploads.delete_task_attachment(scope, file.id)
    refute Repo.get(UploadedFile, file.id)
    refute File.exists?(full_path)
  end

  test "keeps failed physical deletes hidden for cleanup retry", %{org: org, scope: scope} do
    task = insert(:task, organization: org, created_by: scope.user)

    file =
      insert_file(org, scope.user, %{
        context: :mixed_attachment,
        owner_type: "task",
        owner_id: to_string(task.id),
        storage_path: "../outside.pdf"
      })

    assert {:ok, _file} = Uploads.delete_task_attachment(scope, file.id)

    failed_file = Repo.get!(UploadedFile, file.id)
    assert failed_file.deleted_at
    assert failed_file.delete_failed_at
    assert failed_file.delete_error =~ "invalid_storage_path"
    assert {:ok, []} = Uploads.list_task_attachments(scope, task.id)
    assert {:ok, %{failed: 1}} = Uploads.cleanup_deleted_files()
  end

  test "lists email attachments for inbox readers", %{org: org, scope: scope} do
    thread = insert(:email_thread, organization: org)
    email = insert(:email, organization: org, thread: thread)

    file =
      insert_file(org, scope.user, %{
        context: :mixed_attachment,
        owner_type: "email",
        owner_id: to_string(email.id),
        original_filename: "brief.pdf"
      })

    assert {:ok, [found]} = Uploads.list_email_attachments(scope, email.id)
    assert found.id == file.id
  end

  test "lists all attachments in a thread", %{org: org, scope: scope} do
    thread = insert(:email_thread, organization: org)
    email_a = insert(:email, organization: org, thread: thread)
    email_b = insert(:email, organization: org, thread: thread)

    file_a =
      insert_file(org, scope.user, %{
        context: :mixed_attachment,
        owner_type: "email",
        owner_id: to_string(email_a.id),
        original_filename: "one.pdf"
      })

    file_b =
      insert_file(org, scope.user, %{
        context: :mixed_attachment,
        owner_type: "email",
        owner_id: to_string(email_b.id),
        original_filename: "two.pdf"
      })

    assert {:ok, files} = Uploads.list_thread_attachments(scope, thread.id)
    assert Enum.sort(Enum.map(files, & &1.id)) == Enum.sort([file_a.id, file_b.id])
  end

  test "lists draft email attachments and loads bytes for delivery", %{org: org, scope: scope} do
    uploads_root = tmp_uploads_root("email-draft-delivery")
    previous_root = Application.get_env(:konevo, :uploads_root)
    Application.put_env(:konevo, :uploads_root, uploads_root)

    on_exit(fn ->
      restore_env(:konevo, :uploads_root, previous_root)
      File.rm_rf!(uploads_root)
    end)

    draft_owner_id = Ecto.UUID.generate()
    storage_path = "attachments/#{org.id}/#{draft_owner_id}/draft.pdf"
    full_path = Path.join(uploads_root, storage_path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, "%PDF-1.7\n")

    file =
      insert_file(org, scope.user, %{
        context: :mixed_attachment,
        owner_type: "email_draft",
        owner_id: draft_owner_id,
        storage_path: storage_path,
        original_filename: "draft.pdf",
        byte_size: 9
      })

    assert {:ok, [found]} = Uploads.list_email_draft_attachments(scope, draft_owner_id)
    assert found.id == file.id

    assert {:ok, [attachment]} =
             Uploads.email_draft_attachments_for_delivery(scope, draft_owner_id, [
               to_string(file.id)
             ])

    assert attachment.id == file.id
    assert attachment.filename == "draft.pdf"
    assert attachment.content_type == "application/pdf"
    assert attachment.bytes == "%PDF-1.7\n"
  end

  test "claims draft email attachments for a sent email", %{org: org, scope: scope} do
    thread = insert(:email_thread, organization: org, has_attachments: false)
    email = insert(:email, organization: org, thread: thread, has_attachments: false)
    draft_owner_id = Ecto.UUID.generate()

    file =
      insert_file(org, scope.user, %{
        context: :mixed_attachment,
        owner_type: "email_draft",
        owner_id: draft_owner_id,
        original_filename: "claim.pdf"
      })

    assert {:ok, [claimed]} =
             Uploads.claim_email_draft_attachments(scope, draft_owner_id, [file.id], email)

    assert claimed.owner_type == "email"
    assert claimed.owner_id == to_string(email.id)

    assert %UploadedFile{owner_type: "email", owner_id: owner_id} =
             Repo.get!(UploadedFile, file.id)

    assert owner_id == to_string(email.id)
    assert Repo.get!(Email, email.id).has_attachments
    assert Repo.get!(EmailThread, thread.id).has_attachments
  end

  test "deletes draft email attachment record and storage file", %{org: org, scope: scope} do
    uploads_root = tmp_uploads_root("email-draft-delete")
    previous_root = Application.get_env(:konevo, :uploads_root)
    Application.put_env(:konevo, :uploads_root, uploads_root)

    on_exit(fn ->
      restore_env(:konevo, :uploads_root, previous_root)
      File.rm_rf!(uploads_root)
    end)

    draft_owner_id = Ecto.UUID.generate()
    storage_path = "attachments/#{org.id}/#{draft_owner_id}/delete.pdf"
    full_path = Path.join(uploads_root, storage_path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, "%PDF-1.7\n")

    file =
      insert_file(org, scope.user, %{
        context: :mixed_attachment,
        owner_type: "email_draft",
        owner_id: draft_owner_id,
        storage_path: storage_path,
        original_filename: "delete.pdf"
      })

    assert {:ok, _file} = Uploads.delete_email_draft_attachment(scope, file.id, draft_owner_id)
    refute Repo.get(UploadedFile, file.id)
    refute File.exists?(full_path)
  end

  defp insert_file(org, user, overrides) do
    id = System.unique_integer([:positive])

    attrs = %{
      context: :document,
      tenant_id: to_string(org.id),
      original_filename: "file.pdf",
      storage_path: "documents/#{org.id}/#{user.id}/#{id}.pdf",
      content_type: "application/pdf",
      byte_size: 1_048_576,
      sha256: String.duplicate("a", 64),
      owner_type: "user",
      owner_id: to_string(user.id),
      scan_status: :scanned
    }

    Repo.insert!(struct(UploadedFile, Map.merge(attrs, overrides)))
  end

  defp tmp_uploads_root(prefix) do
    Path.join([
      File.cwd!(),
      "tmp",
      "#{prefix}-#{System.unique_integer([:positive])}"
    ])
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
