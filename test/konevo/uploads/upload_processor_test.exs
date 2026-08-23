defmodule Konevo.Uploads.UploadProcessorTest do
  @moduledoc """
  End-to-end tests for UploadProcessor.

  These tests verify that the pipeline:
  - Produces a DB row with the *sniffed* content type (not client-claimed)
  - Stores the *post-processing* byte size (not the pre-resize client claim)
  - Rejects files that fail any validation stage (fail-closed)
  - Never writes files to the permanent upload tree on any error
  """

  use Konevo.DataCase, async: false

  import Konevo.Factory

  alias Konevo.Repo
  alias Konevo.Uploads.{UploadConfig, UploadedFile, UploadPath, UploadProcessor}

  # ---- Helpers ----------------------------------------------------------------

  defp jpeg_magic_bytes do
    # Minimal JPEG with correct magic bytes (not a valid full JPEG but enough for sniffing)
    <<0xFF, 0xD8, 0xFF, 0xE0>> <> String.duplicate(<<0>>, 60)
  end

  defp pdf_magic_bytes do
    <<"%PDF-1.7\n">> <> String.duplicate(<<0>>, 55)
  end

  defp shell_script_bytes do
    "#!/bin/bash\nrm -rf /tmp/important\n"
  end

  defp write_tmp(content, ext) do
    path =
      Path.join(System.tmp_dir!(), "processor_test_#{:erlang.unique_integer([:positive])}#{ext}")

    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp sample_tenant_id do
    # Use integer-based IDs from factory
    org = insert(:organization)
    to_string(org.id)
  end

  defp sample_owner_id do
    user = insert(:user)
    to_string(user.id)
  end

  # Clear any uploaded test files after each test
  setup do
    tenant_id = sample_tenant_id()
    owner_id = sample_owner_id()
    %{tenant_id: tenant_id, owner_id: owner_id}
  end

  describe "temporary source validation" do
    test "rejects source paths outside the system temp directory", %{tenant_id: t, owner_id: o} do
      path = Path.join(File.cwd!(), "untrusted-upload-source.pdf")
      File.write!(path, pdf_magic_bytes())
      on_exit(fn -> File.rm(path) end)

      assert {:error, :invalid_temp_path} =
               UploadProcessor.process(path, :document, t, o, "user", "report.pdf")
    end
  end

  # ---- Extension validation ---------------------------------------------------

  describe "extension validation (step 1)" do
    test "rejects disallowed extension for context", %{tenant_id: t, owner_id: o} do
      path = write_tmp(jpeg_magic_bytes(), ".exe")

      assert {:error, {:extension_not_allowed, ".exe"}} =
               UploadProcessor.process(path, :avatar, t, o, "user", "malware.exe")
    end

    test "rejects files with no extension", %{tenant_id: t, owner_id: o} do
      path = write_tmp(jpeg_magic_bytes(), "")
      assert {:error, _} = UploadProcessor.process(path, :avatar, t, o, "user", "noext")
    end
  end

  # ---- MIME validation --------------------------------------------------------

  describe "client MIME validation (step 3)" do
    test "rejects file whose extension maps to disallowed MIME for context", %{
      tenant_id: t,
      owner_id: o
    } do
      # .csv is not allowed in :avatar context
      path = write_tmp(jpeg_magic_bytes(), ".csv")

      assert {:error, {:client_mime_not_allowed, _}} =
               UploadProcessor.process(path, :avatar, t, o, "user", "photo.csv")
    end
  end

  # ---- Content sniffing (step 5) — the core security test --------------------

  describe "magic-byte content sniffing" do
    test "rejects a shell script with .jpg extension (spoofed extension attack)", %{
      tenant_id: t,
      owner_id: o
    } do
      path = write_tmp(shell_script_bytes(), ".jpg")

      result = UploadProcessor.process(path, :avatar, t, o, "user", "photo.jpg")

      # Must be rejected; no DB record must be created
      assert {:error, _} = result
      assert Repo.aggregate(UploadedFile, :count) == 0
    end

    test "rejects a PDF renamed to .jpg", %{tenant_id: t, owner_id: o} do
      path = write_tmp(pdf_magic_bytes(), ".jpg")

      result = UploadProcessor.process(path, :avatar, t, o, "user", "photo.jpg")

      # PDF is not in avatar's type_families ([:jpeg, :png, :gif, :webp])
      assert {:error, {:content_type_not_allowed, :pdf}} = result
      assert Repo.aggregate(UploadedFile, :count) == 0
    end

    test "rejects a JPEG uploaded to :document context (wrong type family)", %{
      tenant_id: t,
      owner_id: o
    } do
      path = write_tmp(jpeg_magic_bytes(), ".jpg")

      # :document context doesn't allow image families
      result = UploadProcessor.process(path, :document, t, o, "user", "photo.jpg")

      assert {:error, {:client_mime_not_allowed, _}} = result
    end
  end

  # ---- File size validation ---------------------------------------------------

  describe "file size validation (step 4)" do
    test "rejects a file exceeding the context's max_file_size", %{tenant_id: t, owner_id: o} do
      # :avatar allows max 5 MB; write 6 MB of data with JPEG magic bytes
      oversized = jpeg_magic_bytes() <> :crypto.strong_rand_bytes(6 * 1024 * 1024)
      path = write_tmp(oversized, ".jpg")

      assert {:error, {:file_too_large, _, _}} =
               UploadProcessor.process(path, :avatar, t, o, "user", "big.jpg")
    end
  end

  # ---- Happy path — end-to-end ------------------------------------------------

  describe "happy path (step 13-14): DB record correctness" do
    test "produces a DB row with the sniffed content type, not the client claim", %{
      tenant_id: t,
      owner_id: o
    } do
      # Use PDF magic bytes, correct .pdf extension, correct context
      path = write_tmp(pdf_magic_bytes(), ".pdf")

      assert {:ok, %UploadedFile{} = file} =
               UploadProcessor.process(path, :document, t, o, "user", "report.pdf")

      # Content type must come from the sniffer, not from the client filename
      assert file.content_type == "application/pdf"
      assert file.context == :document
      assert file.tenant_id == t
      assert file.owner_id == o
      assert file.scan_status == :scanned
      assert file.sha256 != nil
      assert file.byte_size > 0

      # The stored filename is display-sanitized, never a raw filesystem path
      assert file.original_filename =~ "report"
      refute String.contains?(file.original_filename, "/")
      refute String.contains?(file.original_filename, "\\")

      # The storage path must be under the correct context subdir and tenant
      config = UploadConfig.get!(:document)
      assert String.starts_with?(file.storage_path, config.storage_subdir)
      assert String.contains?(file.storage_path, t)

      # Clean up the actual uploaded file
      full_path = UploadPath.expand(file.storage_path)
      on_exit(fn -> File.rm(full_path) end)
    end

    test "byte_size in DB reflects post-processing on-disk size", %{tenant_id: t, owner_id: o} do
      path = write_tmp(pdf_magic_bytes(), ".pdf")
      _original_size = File.stat!(path).size

      assert {:ok, %UploadedFile{} = file} =
               UploadProcessor.process(path, :document, t, o, "user", "report.pdf")

      # Post-process size is the actual file size after the pipeline
      on_disk_size = File.stat!(UploadPath.expand(file.storage_path)).size
      assert file.byte_size == on_disk_size

      # The client's pre-upload size is not blindly stored
      # (for non-resized files they may match — the key is it's the on-disk value)
      assert is_integer(file.byte_size)
      assert file.byte_size > 0

      on_exit(fn ->
        full_path = UploadPath.expand(file.storage_path)
        File.rm(full_path)
      end)
    end

    test "sha256 field is a lowercase hex string of 64 chars (SHA-256)", %{
      tenant_id: t,
      owner_id: o
    } do
      path = write_tmp(pdf_magic_bytes(), ".pdf")

      assert {:ok, file} = UploadProcessor.process(path, :document, t, o, "user", "doc.pdf")

      assert String.length(file.sha256) == 64
      assert file.sha256 =~ ~r/^[0-9a-f]{64}$/

      on_exit(fn ->
        full_path = UploadPath.expand(file.storage_path)
        File.rm(full_path)
      end)
    end

    test "no file is written to permanent storage when pipeline fails", %{
      tenant_id: t,
      owner_id: o
    } do
      # Shell script with .jpg extension: fails at content sniff (step 5)
      path = write_tmp(shell_script_bytes(), ".jpg")
      uploads_root = UploadConfig.uploads_root()

      file_count_before =
        case File.ls(uploads_root) do
          {:ok, files} -> length(files)
          {:error, _} -> 0
        end

      UploadProcessor.process(path, :avatar, t, o, "user", "evil.jpg")

      file_count_after =
        case File.ls(uploads_root) do
          {:ok, files} -> length(files)
          {:error, _} -> 0
        end

      assert file_count_after == file_count_before
    end
  end

  # ---- Sanitize display filename ----------------------------------------------

  describe "original_filename sanitization" do
    test "strips path separators from the stored display filename", %{tenant_id: t, owner_id: o} do
      path = write_tmp(pdf_magic_bytes(), ".pdf")

      # Filename with path traversal attempt
      assert {:ok, file} =
               UploadProcessor.process(path, :document, t, o, "user", "../../../etc/report.pdf")

      refute String.contains?(file.original_filename, "/")
      refute String.contains?(file.original_filename, "\\")
      refute String.contains?(file.original_filename, "..")

      on_exit(fn ->
        full_path = UploadPath.expand(file.storage_path)
        File.rm(full_path)
      end)
    end
  end
end
