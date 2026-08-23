defmodule Konevo.Uploads.UploadPathTest do
  use ExUnit.Case, async: true

  alias Konevo.Uploads.{PathTraversalError, UploadConfig, UploadPath}

  describe "sanitize_scope_segment/1" do
    test "accepts valid alphanumeric IDs" do
      assert UploadPath.sanitize_scope_segment("tenant-123") == "tenant-123"
      assert UploadPath.sanitize_scope_segment("user-abc-xyz") == "user-abc-xyz"
      assert UploadPath.sanitize_scope_segment("a") == "a"
    end

    test "accepts hyphens and numbers" do
      assert UploadPath.sanitize_scope_segment("123-456-789") == "123-456-789"
      assert UploadPath.sanitize_scope_segment("ABC-def-123") == "ABC-def-123"
    end

    test "rejects path separators" do
      assert_raise PathTraversalError, fn ->
        UploadPath.sanitize_scope_segment("tenant/123")
      end

      assert_raise PathTraversalError, fn ->
        UploadPath.sanitize_scope_segment("tenant\\123")
      end
    end

    test "rejects shell metacharacters" do
      assert_raise PathTraversalError, fn ->
        UploadPath.sanitize_scope_segment("tenant;rm -rf")
      end

      assert_raise PathTraversalError, fn ->
        UploadPath.sanitize_scope_segment("tenant$(whoami)")
      end
    end

    test "rejects dots and special characters" do
      assert_raise PathTraversalError, fn ->
        UploadPath.sanitize_scope_segment("tenant.example.com")
      end

      assert_raise PathTraversalError, fn ->
        UploadPath.sanitize_scope_segment("tenant@domain")
      end
    end

    test "rejects extremely long strings" do
      long_str = String.duplicate("a", 100)

      assert_raise PathTraversalError, fn ->
        UploadPath.sanitize_scope_segment(long_str)
      end
    end

    test "rejects empty string" do
      assert_raise PathTraversalError, fn ->
        UploadPath.sanitize_scope_segment("")
      end
    end
  end

  describe "extract_and_validate_extension/1" do
    test "accepts valid extensions" do
      assert UploadPath.extract_and_validate_extension("file.jpg") == ".jpg"
      assert UploadPath.extract_and_validate_extension("document.pdf") == ".pdf"
      assert UploadPath.extract_and_validate_extension("data.csv") == ".csv"
    end

    test "accepts mixed case and normalizes to lowercase" do
      assert UploadPath.extract_and_validate_extension("file.JPG") == ".jpg"
      assert UploadPath.extract_and_validate_extension("file.PdF") == ".pdf"
    end

    test "rejects multiple dots in extension" do
      assert_raise PathTraversalError, fn ->
        UploadPath.extract_and_validate_extension("file.tar.gz")
      end
    end

    test "rejects extensions with shell metacharacters" do
      assert_raise PathTraversalError, fn ->
        UploadPath.extract_and_validate_extension("file.jpg;rm")
      end

      assert_raise PathTraversalError, fn ->
        UploadPath.extract_and_validate_extension("file.jpg$(whoami)")
      end
    end

    test "rejects extremely long extensions" do
      assert_raise PathTraversalError, fn ->
        UploadPath.extract_and_validate_extension("file.verylongextension")
      end
    end

    test "rejects files with no extension" do
      assert_raise PathTraversalError, fn ->
        UploadPath.extract_and_validate_extension("filewithoutext")
      end
    end
  end

  describe "build_destination/5" do
    test "builds a valid destination path" do
      path =
        UploadPath.build_destination(
          :avatar,
          "tenant-123",
          "user-456",
          "photo.jpg",
          "uuid-here"
        )

      # Should follow pattern: avatars/<tenant>/<owner>/<uuid>.ext
      assert String.starts_with?(path, "avatars/tenant-123/user-456/uuid-here.jpg")
    end

    test "validates all path components" do
      # Invalid tenant
      assert_raise PathTraversalError, fn ->
        UploadPath.build_destination(
          :avatar,
          "tenant/../../etc/passwd",
          "user-456",
          "photo.jpg",
          "uuid"
        )
      end

      # Invalid owner
      assert_raise PathTraversalError, fn ->
        UploadPath.build_destination(
          :avatar,
          "tenant-123",
          "user;rm -rf",
          "photo.jpg",
          "uuid"
        )
      end

      # Invalid filename
      assert_raise PathTraversalError, fn ->
        UploadPath.build_destination(
          :avatar,
          "tenant-123",
          "user-456",
          "photo.exe;whoami",
          "uuid"
        )
      end
    end

    test "generates context-specific subdirectory" do
      avatar_path =
        UploadPath.build_destination(:avatar, "t1", "u1", "pic.jpg", "uuid1")

      doc_path =
        UploadPath.build_destination(:document, "t1", "u1", "file.pdf", "uuid2")

      assert String.starts_with?(avatar_path, "avatars/")
      assert String.starts_with?(doc_path, "documents/")
    end
  end

  describe "assert_within_root!/1" do
    test "accepts paths within the uploads root" do
      uploads_root = UploadConfig.uploads_root()
      path = Path.join(uploads_root, "avatars/tenant/user/uuid.jpg")

      result = UploadPath.assert_within_root!(path)
      assert String.contains?(result, "avatars")
    end

    test "rejects path traversal attempts" do
      uploads_root = UploadConfig.uploads_root()
      malicious_path = Path.join(uploads_root, "avatars/tenant/../../etc/passwd")

      assert_raise PathTraversalError, fn ->
        UploadPath.assert_within_root!(malicious_path)
      end
    end

    test "rejects absolute paths outside uploads root" do
      assert_raise PathTraversalError, fn ->
        UploadPath.assert_within_root!("/etc/passwd")
      end
    end

    test "rejects sibling paths sharing the uploads root prefix" do
      sibling_path = UploadConfig.uploads_root() <> "_evil/file.pdf"

      assert_raise PathTraversalError, fn ->
        UploadPath.assert_within_root!(sibling_path)
      end
    end

    test "rejects paths with excessive dot-dot sequences" do
      uploads_root = UploadConfig.uploads_root()

      malicious =
        Path.join([
          uploads_root,
          "avatars/tenant",
          "../..",
          "../..",
          "../..",
          "etc/passwd"
        ])

      assert_raise PathTraversalError, fn ->
        UploadPath.assert_within_root!(malicious)
      end
    end
  end

  describe "resolve_for_serving/2" do
    test "rejects traversal in stored paths" do
      assert {:error, :invalid_storage_path} =
               UploadPath.resolve_for_serving("documents/tenant/../../secret.pdf", "tenant")
    end
  end

  describe "extract_tenant_id/1" do
    test "extracts tenant from standard path format" do
      path = "avatars/tenant-123/user-456/uuid.jpg"
      assert UploadPath.extract_tenant_id(path) == "tenant-123"
    end

    test "returns nil for malformed paths" do
      assert UploadPath.extract_tenant_id("malformed") == nil
      assert UploadPath.extract_tenant_id("avatars/only/two") == nil
    end
  end

  describe "assert_tenant_segment!/2" do
    test "accepts matching tenant segments" do
      path = "avatars/tenant-123/user-456/uuid.jpg"
      assert UploadPath.assert_tenant_segment!(path, "tenant-123") == :ok
    end

    test "rejects mismatching tenant segments" do
      path = "avatars/tenant-123/user-456/uuid.jpg"

      assert_raise PathTraversalError, fn ->
        UploadPath.assert_tenant_segment!(path, "tenant-999")
      end
    end

    test "catches attempted tenant spoofing" do
      # Attempt to use a different tenant's storage path
      path = "avatars/other-tenant/user-456/uuid.jpg"

      assert_raise PathTraversalError, fn ->
        UploadPath.assert_tenant_segment!(path, "my-tenant")
      end
    end
  end
end
