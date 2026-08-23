defmodule Konevo.Uploads.UploadConfigTest do
  use ExUnit.Case, async: true

  alias Konevo.Uploads.UploadConfig

  describe "get!/1" do
    test "returns config for known contexts" do
      config = UploadConfig.get!(:avatar)
      assert config.storage_subdir == "avatars"
      assert config.max_file_size == 5 * 1024 * 1024
      assert config.max_entries == 1
    end

    test "raises for unknown contexts" do
      assert_raise ArgumentError, fn ->
        UploadConfig.get!(:nonexistent)
      end
    end
  end

  describe "contexts/0" do
    test "returns all available contexts" do
      contexts = UploadConfig.contexts()
      assert :avatar in contexts
      assert :document in contexts
      assert :post_media in contexts
      assert :mixed_attachment in contexts
    end
  end

  describe "cast_context/1" do
    test "safely casts known string contexts to atoms" do
      assert UploadConfig.cast_context("avatar") == {:ok, :avatar}
      assert UploadConfig.cast_context("document") == {:ok, :document}
      assert UploadConfig.cast_context("post_media") == {:ok, :post_media}
      assert UploadConfig.cast_context("mixed_attachment") == {:ok, :mixed_attachment}
    end

    test "returns error for unknown contexts" do
      assert UploadConfig.cast_context("nonexistent") == {:error, :invalid_context}
    end

    test "prevents atom table exhaustion" do
      # Attempting to create arbitrary atoms should fail
      assert UploadConfig.cast_context("some_random_atom_#{:os.system_time()}") ==
               {:error, :invalid_context}
    end

    test "is case sensitive" do
      assert UploadConfig.cast_context("Avatar") == {:error, :invalid_context}
      assert UploadConfig.cast_context("DOCUMENT") == {:error, :invalid_context}
    end
  end

  describe "extension_allowed?/2" do
    test "accepts allowed extensions for context" do
      assert UploadConfig.extension_allowed?(:avatar, ".jpg")
      assert UploadConfig.extension_allowed?(:avatar, ".png")
      assert UploadConfig.extension_allowed?(:document, ".pdf")
      assert UploadConfig.extension_allowed?(:document, ".docx")
    end

    test "rejects disallowed extensions for context" do
      refute UploadConfig.extension_allowed?(:avatar, ".pdf")
      refute UploadConfig.extension_allowed?(:document, ".jpg")
    end

    test "normalizes extension case" do
      assert UploadConfig.extension_allowed?(:avatar, ".JPG")
      assert UploadConfig.extension_allowed?(:avatar, ".Png")
    end
  end

  describe "mime_allowed?/2" do
    test "accepts allowed MIME types for context" do
      assert UploadConfig.mime_allowed?(:avatar, "image/jpeg")
      assert UploadConfig.mime_allowed?(:avatar, "image/png")
      assert UploadConfig.mime_allowed?(:document, "application/pdf")
    end

    test "rejects disallowed MIME types for context" do
      refute UploadConfig.mime_allowed?(:avatar, "application/pdf")
      refute UploadConfig.mime_allowed?(:document, "image/jpeg")
    end

    test "normalizes MIME type case" do
      assert UploadConfig.mime_allowed?(:avatar, "IMAGE/JPEG")
      assert UploadConfig.mime_allowed?(:document, "APPLICATION/PDF")
    end
  end

  describe "size_valid?/2" do
    test "accepts files within size limit" do
      assert UploadConfig.size_valid?(:avatar, 1 * 1024 * 1024)
      assert UploadConfig.size_valid?(:avatar, 5 * 1024 * 1024)
      assert UploadConfig.size_valid?(:document, 20 * 1024 * 1024)
    end

    test "rejects files exceeding size limit" do
      refute UploadConfig.size_valid?(:avatar, 10 * 1024 * 1024)
      refute UploadConfig.size_valid?(:document, 30 * 1024 * 1024)
    end

    test "accepts zero-byte files" do
      assert UploadConfig.size_valid?(:avatar, 0)
    end
  end

  describe "context configurations" do
    test "avatar context is properly configured" do
      config = UploadConfig.get!(:avatar)
      assert config.storage_subdir == "avatars"
      assert config.max_file_size == 5 * 1024 * 1024
      assert config.max_entries == 1
      assert config.strip_image_metadata == true
      assert config.max_image_dimension == 512
      assert config.image_quality == 85
    end

    test "document context is properly configured" do
      config = UploadConfig.get!(:document)
      assert config.storage_subdir == "documents"
      assert config.max_file_size == 25 * 1024 * 1024
      assert config.max_entries == 5
      assert config.strip_image_metadata == false
      assert config.max_image_dimension == nil
      assert config.image_quality == nil
    end

    test "post_media context includes all media types" do
      config = UploadConfig.get!(:post_media)
      assert config.storage_subdir == "post_media"
      assert config.max_file_size == 500 * 1024 * 1024
      assert config.max_entries == 10
      assert config.max_image_dimension == 2000
      assert config.image_quality == 85
    end

    test "mixed_attachment context is a union of all types" do
      config = UploadConfig.get!(:mixed_attachment)
      assert config.storage_subdir == "attachments"
      assert config.max_file_size == 100 * 1024 * 1024
      assert config.max_entries == 10
      assert config.max_image_dimension == 1600
      assert config.image_quality == 85
    end
  end

  describe "allowed extensions for each context" do
    test "avatar accepts image extensions only" do
      avatar_config = UploadConfig.get!(:avatar)
      assert ".jpg" in avatar_config.allowed_extensions
      assert ".png" in avatar_config.allowed_extensions
      assert ".gif" in avatar_config.allowed_extensions
      refute ".pdf" in avatar_config.allowed_extensions
    end

    test "document accepts document extensions only" do
      doc_config = UploadConfig.get!(:document)
      assert ".pdf" in doc_config.allowed_extensions
      assert ".docx" in doc_config.allowed_extensions
      assert ".xlsx" in doc_config.allowed_extensions
      refute ".jpg" in doc_config.allowed_extensions
    end

    test "mixed_attachment accepts all types" do
      mixed_config = UploadConfig.get!(:mixed_attachment)
      assert ".jpg" in mixed_config.allowed_extensions
      assert ".pdf" in mixed_config.allowed_extensions
      assert ".mp4" in mixed_config.allowed_extensions
      assert ".mp3" in mixed_config.allowed_extensions
    end
  end
end
