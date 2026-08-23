defmodule Konevo.Uploads.UploadedFileTest do
  use Konevo.DataCase, async: true

  alias Konevo.Uploads.UploadedFile

  describe "changeset/2" do
    test "validates required fields" do
      changeset = UploadedFile.changeset(%UploadedFile{}, %{})

      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).context
      assert "can't be blank" in errors_on(changeset).tenant_id
      assert "can't be blank" in errors_on(changeset).original_filename
      assert "can't be blank" in errors_on(changeset).storage_path
    end

    test "validates with valid attributes" do
      attrs = %{
        context: :avatar,
        tenant_id: "tenant-123",
        original_filename: "profile.jpg",
        storage_path: "avatars/tenant-123/user-456/uuid.jpg",
        content_type: "image/jpeg",
        byte_size: 51_200,
        sha256: "abcdef1234567890",
        owner_type: "user",
        owner_id: "user-456",
        scan_status: :scanned
      }

      changeset = UploadedFile.changeset(%UploadedFile{}, attrs)
      assert changeset.valid?
    end

    test "enforces valid scan_status enum" do
      attrs = %{
        context: :avatar,
        tenant_id: "tenant-123",
        original_filename: "profile.jpg",
        storage_path: "avatars/tenant-123/user-456/uuid.jpg",
        content_type: "image/jpeg",
        byte_size: 51_200,
        sha256: "abcdef1234567890",
        owner_type: "user",
        owner_id: "user-456",
        scan_status: :invalid_status
      }

      changeset = UploadedFile.changeset(%UploadedFile{}, attrs)
      assert changeset.valid? == false
    end

    test "enforces valid context enum" do
      attrs = %{
        context: :invalid_context,
        tenant_id: "tenant-123",
        original_filename: "profile.jpg",
        storage_path: "avatars/tenant-123/user-456/uuid.jpg",
        content_type: "image/jpeg",
        byte_size: 51_200,
        sha256: "abcdef1234567890",
        owner_type: "user",
        owner_id: "user-456",
        scan_status: :scanned
      }

      changeset = UploadedFile.changeset(%UploadedFile{}, attrs)
      assert changeset.valid? == false
    end

    test "stores all provided attributes" do
      attrs = %{
        context: :document,
        tenant_id: "org-789",
        original_filename: "report.pdf",
        storage_path: "documents/org-789/user-123/uuid.pdf",
        content_type: "application/pdf",
        byte_size: 102_400,
        sha256: "xyz9876543210",
        owner_type: "organization",
        owner_id: "org-789",
        scan_status: :scanned
      }

      changeset = UploadedFile.changeset(%UploadedFile{}, attrs)
      assert changeset.changes == attrs
    end
  end
end
