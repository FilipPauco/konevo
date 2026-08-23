defmodule KonevoWeb.UploadControllerTest do
  @moduledoc """
  Tests for the authenticated file-serving controller.

  Critical property: any authorization failure returns 404, never 403,
  to prevent distinguishing "doesn't exist" from "exists but isn't yours".
  """

  use KonevoWeb.ConnCase, async: false

  import Konevo.Factory

  alias Konevo.Repo
  alias Konevo.Uploads.{UploadedFile, UploadPath}

  # ---- Helpers ----------------------------------------------------------------

  defp org_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}

  # Insert a real UploadedFile record without actually uploading a file.
  defp insert_file_record(attrs) do
    Repo.insert!(%UploadedFile{
      context: :document,
      tenant_id: attrs[:tenant_id] || "default-tenant",
      original_filename: attrs[:original_filename] || "report.pdf",
      storage_path: attrs[:storage_path] || "documents/#{attrs[:tenant_id] || "t1"}/u1/test.pdf",
      content_type: "application/pdf",
      byte_size: 1024,
      sha256: "a" <> String.duplicate("b", 63),
      owner_type: "user",
      owner_id: attrs[:owner_id] || "user-1",
      scan_status: :scanned,
      deleted_at: attrs[:deleted_at]
    })
  end

  # ---- Setup ------------------------------------------------------------------

  setup do
    # Org A — "our" tenant
    user_a = insert(:user)
    org_a = insert(:organization)
    _membership_a = insert(:membership, user: user_a, organization: org_a, role: :owner)

    # Org B — a different tenant; its files must never be served to org_a users
    user_b = insert(:user)
    org_b = insert(:organization)
    _membership_b = insert(:membership, user: user_b, organization: org_b, role: :owner)

    conn_a = build_conn() |> log_in_user(user_a) |> org_conn(org_a)

    %{
      user_a: user_a,
      org_a: org_a,
      conn_a: conn_a,
      user_b: user_b,
      org_b: org_b
    }
  end

  # ---- Authentication gate ----------------------------------------------------

  describe "unauthenticated access" do
    test "redirects to login, returns no file content", %{org_a: org_a} do
      file =
        insert_file_record(
          tenant_id: "doesnt-matter",
          owner_id: "doesnt-matter",
          storage_path: "documents/doesnt-matter/u/uuid.pdf"
        )

      unauthenticated = build_conn() |> org_conn(org_a)
      response = get(unauthenticated, ~p"/uploads/document/#{file.id}")

      # Should redirect to login, not serve the file
      assert response.status in [302, 401]
    end
  end

  # ---- Cross-tenant isolation — the most security-critical test ---------------

  describe "cross-tenant isolation" do
    test "a file belonging to org_b returns 404 when accessed by org_a user", %{
      conn_a: conn_a,
      org_b: org_b,
      user_b: user_b
    } do
      # File owned by org_b
      file =
        insert_file_record(
          tenant_id: to_string(org_b.id),
          owner_id: to_string(user_b.id),
          storage_path: "documents/#{org_b.id}/#{user_b.id}/secret.pdf"
        )

      # Org_a user requests org_b's file
      response = get(conn_a, ~p"/uploads/document/#{file.id}")

      # Must be 404 — not 200 (file served) and not 403 (existence confirmed)
      assert response.status == 404
    end

    test "returns 404, not 403, for cross-tenant access (no existence leak)", %{
      conn_a: conn_a,
      org_b: org_b,
      user_b: user_b
    } do
      file =
        insert_file_record(
          tenant_id: to_string(org_b.id),
          owner_id: to_string(user_b.id),
          storage_path: "documents/#{org_b.id}/#{user_b.id}/confidential.pdf"
        )

      response = get(conn_a, ~p"/uploads/document/#{file.id}")

      assert response.status == 404
      refute response.status == 403
    end

    test "file with matching tenant returns 404 when file is missing from disk", %{
      conn_a: conn_a,
      org_a: org_a,
      user_a: user_a
    } do
      # DB record exists but the file is NOT on disk
      file =
        insert_file_record(
          tenant_id: to_string(org_a.id),
          owner_id: to_string(user_a.id),
          storage_path: "documents/#{org_a.id}/#{user_a.id}/missing-on-disk.pdf"
        )

      response = get(conn_a, ~p"/uploads/document/#{file.id}")

      # File missing on disk → 404
      assert response.status == 404
    end

    test "returns 404 for a traversing stored path", %{
      conn_a: conn_a,
      org_a: org_a,
      user_a: user_a
    } do
      file =
        insert_file_record(
          tenant_id: to_string(org_a.id),
          owner_id: to_string(user_a.id),
          storage_path: "documents/#{org_a.id}/../../mix.exs"
        )

      response = get(conn_a, ~p"/uploads/document/#{file.id}")

      assert response.status == 404
      refute response.resp_body =~ "defmodule"
    end
  end

  # ---- Invalid context param --------------------------------------------------

  describe "invalid context parameter" do
    test "returns 404 for unknown context strings", %{conn_a: conn_a} do
      response = get(conn_a, "/uploads/unknown_context/12345")
      assert response.status == 404
    end

    test "returns 404 for context mismatch (file is :avatar but asked for :document)", %{
      conn_a: conn_a,
      org_a: org_a,
      user_a: user_a
    } do
      # Insert an :avatar file but request it under :document context
      avatar_file =
        Repo.insert!(%UploadedFile{
          context: :avatar,
          tenant_id: to_string(org_a.id),
          original_filename: "photo.jpg",
          storage_path: "avatars/#{org_a.id}/#{user_a.id}/uuid.jpg",
          content_type: "image/jpeg",
          byte_size: 1024,
          sha256: String.duplicate("c", 64),
          owner_type: "user",
          owner_id: to_string(user_a.id),
          scan_status: :scanned
        })

      # Request it under the wrong context path
      response = get(conn_a, ~p"/uploads/document/#{avatar_file.id}")
      assert response.status == 404
    end
  end

  # ---- Non-existent file IDs --------------------------------------------------

  describe "non-existent file" do
    test "returns 404 for a non-existent file ID", %{conn_a: conn_a} do
      response = get(conn_a, ~p"/uploads/document/999999999")
      assert response.status == 404
    end

    test "returns 404 for a soft-deleted file", %{
      conn_a: conn_a,
      org_a: org_a,
      user_a: user_a
    } do
      file =
        insert_file_record(
          tenant_id: to_string(org_a.id),
          owner_id: to_string(user_a.id),
          deleted_at: DateTime.utc_now(:second)
        )

      response = get(conn_a, ~p"/uploads/document/#{file.id}")

      assert response.status == 404
    end
  end

  describe "file disposition" do
    test "previews task-owned mixed attachments for the current org", %{
      conn_a: conn_a,
      org_a: org_a,
      user_a: user_a
    } do
      task = insert(:task, organization: org_a, created_by: user_a)
      storage_path = "attachments/#{org_a.id}/#{task.id}/preview.jpg"
      full_path = UploadPath.expand(storage_path)
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, <<0xFF, 0xD8, 0xFF, 0xD9>>)
      on_exit(fn -> File.rm(full_path) end)

      file =
        Repo.insert!(%UploadedFile{
          context: :mixed_attachment,
          tenant_id: to_string(org_a.id),
          original_filename: "preview.jpg",
          storage_path: storage_path,
          content_type: "image/jpeg",
          byte_size: 4,
          sha256: String.duplicate("d", 64),
          owner_type: "task",
          owner_id: to_string(task.id),
          scan_status: :scanned
        })

      response = get(conn_a, ~p"/uploads/mixed_attachment/#{file.id}?preview=true")

      assert response.status == 200
      assert response.resp_body == <<0xFF, 0xD8, 0xFF, 0xD9>>
      assert ["image/jpeg"] = get_resp_header(response, "content-type")
      assert [disposition] = get_resp_header(response, "content-disposition")
      assert String.starts_with?(disposition, "inline;")
    end

    test "previews supported files inline", %{conn_a: conn_a, org_a: org_a, user_a: user_a} do
      storage_path = "documents/#{org_a.id}/#{user_a.id}/preview.pdf"
      full_path = UploadPath.expand(storage_path)
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, "%PDF-1.7\npreview")
      on_exit(fn -> File.rm(full_path) end)

      file =
        insert_file_record(
          tenant_id: to_string(org_a.id),
          owner_id: to_string(user_a.id),
          storage_path: storage_path
        )

      response = get(conn_a, ~p"/uploads/document/#{file.id}?preview=true")

      assert [disposition] = get_resp_header(response, "content-disposition")
      assert String.starts_with?(disposition, "inline;")
      assert [preview_csp] = get_resp_header(response, "content-security-policy")
      assert preview_csp =~ "frame-ancestors 'self'"
      refute preview_csp =~ "frame-ancestors 'none'"

      download_response = get(conn_a, ~p"/uploads/document/#{file.id}")
      assert [download_csp] = get_resp_header(download_response, "content-security-policy")
      assert download_csp =~ "frame-ancestors 'none'"
    end
  end
end
