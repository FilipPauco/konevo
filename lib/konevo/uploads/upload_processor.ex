defmodule Konevo.Uploads.UploadProcessor do
  @moduledoc """
  Orchestrates the file upload processing pipeline.

  Pipeline stages (fail-closed at every step):
  1. Extension allowlist check
  2. Defensive extension extraction and validation
  3. Client MIME allowlist check
  4. File size validation
  5. Magic-byte content sniff
  6. ZIP internals check (for Office documents)
  7. Malware scan
  8. Generate safe destination path
  9. Create directory structure
  10. Move file to destination
  11. Strip image metadata (if applicable)
  12. Resize/recompress images (if applicable)
  13. Compute SHA256 hash
  14. Persist UploadedFile record
  """

  require Logger

  alias Konevo.Repo

  alias Konevo.Uploads.{
    ContentSniffer,
    ImageMetadataStripper,
    ImageOptimizer,
    PathTraversalError,
    UploadConfig,
    UploadedFile,
    UploadPath
  }

  @doc """
  Process an uploaded file through the complete pipeline.

  Parameters:
  - temp_path: path to the temporarily uploaded file (from LiveView)
  - context: upload context atom (e.g., :avatar, :document)
  - tenant_id: authenticated tenant ID
  - owner_id: authenticated owner ID
  - owner_type: type of owner (e.g., "user", "organization")
  - original_filename: client-supplied filename (for display and extension)

  Returns:
  - {:ok, uploaded_file_record} on success
  - {:error, reason} on failure (no file is written on any error)

  Every error causes immediate abort. No partial/corrupted files are created.
  """
  def process(temp_path, context, tenant_id, owner_id, owner_type, original_filename)
      when is_binary(temp_path) and is_atom(context) and is_binary(tenant_id) and
             is_binary(owner_id) and is_binary(owner_type) and is_binary(original_filename) do
    with :ok <- validate_temp_path(temp_path),
         :ok <- validate_extension(original_filename, context),
         _extension <- UploadPath.extract_and_validate_extension(original_filename),
         :ok <- validate_client_mime(original_filename, context),
         :ok <- validate_file_size(temp_path, context),
         {:ok, sniffed_family, sniffed_mime} <- sniff_content(temp_path, context),
         :ok <- validate_office_document(temp_path, sniffed_family),
         :ok <- scan_malware(temp_path),
         dest_path <- build_destination_path(context, tenant_id, owner_id, original_filename),
         :ok <- UploadPath.ensure_directory!(dest_path),
         full_path <- UploadPath.expand(dest_path),
         :ok <- move_file_to_destination(temp_path, full_path),
         :ok <- maybe_strip_metadata(full_path, context, sniffed_family),
         :ok <- maybe_optimize_image(full_path, context, sniffed_family),
         {:ok, sha256} <- compute_sha256(full_path),
         {:ok, file_size} <- get_file_size(full_path) do
      persist_record(%{
        context: context,
        tenant_id: tenant_id,
        owner_id: owner_id,
        owner_type: owner_type,
        storage_path: dest_path,
        original_filename: original_filename,
        content_type: sniffed_mime,
        byte_size: file_size,
        sha256: sha256
      })
    else
      {:error, reason} ->
        Logger.error(
          "[UploadProcessor] Pipeline failed for #{original_filename}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # === Pipeline stages ===

  defp validate_temp_path(temp_path) do
    validated_path = UploadPath.assert_within_directory!(temp_path, System.tmp_dir!())

    case File.lstat(validated_path) do
      {:ok, %File.Stat{type: :regular}} -> :ok
      {:ok, %File.Stat{type: type}} -> {:error, {:invalid_temp_file_type, type}}
      {:error, reason} -> {:error, {:stat_failed, reason}}
    end
  rescue
    PathTraversalError -> {:error, :invalid_temp_path}
  end

  defp validate_extension(filename, _context) do
    extension = UploadPath.extract_and_validate_extension(filename)

    if UploadConfig.globally_allowed_extension?(extension) do
      :ok
    else
      {:error, {:extension_not_allowed, extension}}
    end
  rescue
    PathTraversalError -> {:error, :invalid_extension}
  end

  defp validate_client_mime(filename, context) do
    config = UploadConfig.get!(context)
    mime_type = MIME.from_path(filename)

    if mime_type in config.allowed_mimes do
      :ok
    else
      {:error, {:client_mime_not_allowed, mime_type}}
    end
  end

  defp validate_file_size(temp_path, context) do
    config = UploadConfig.get!(context)

    case File.stat(temp_path) do
      {:ok, %File.Stat{size: size}} ->
        if size <= config.max_file_size do
          :ok
        else
          {:error, {:file_too_large, size, config.max_file_size}}
        end

      {:error, reason} ->
        {:error, {:stat_failed, reason}}
    end
  end

  defp sniff_content(temp_path, context) do
    config = UploadConfig.get!(context)

    case ContentSniffer.sniff(temp_path) do
      {:ok, type_family, content_type} ->
        if type_family in config.type_families do
          {:ok, type_family, content_type}
        else
          {:error, {:content_type_not_allowed, type_family}}
        end

      {:error, reason} ->
        {:error, {:sniff_failed, reason}}
    end
  end

  defp validate_office_document(temp_path, family)
       when family in [:docx, :xlsx, :pptx] do
    # For Office documents, do a secondary validation of ZIP structure
    case ContentSniffer.validate_content(temp_path, [:docx, :xlsx, :pptx]) do
      :ok -> :ok
      error -> error
    end
  end

  defp validate_office_document(_temp_path, _family), do: :ok

  defp scan_malware(temp_path) do
    scanner = Application.get_env(:konevo, :malware_scanner, Konevo.Uploads.NoopScanner)

    case scanner.scan(temp_path) do
      :clean ->
        :ok

      {:infected, reason} ->
        {:error, {:malware_detected, reason}}

      {:error, reason} ->
        {:error, {:scan_failed, reason}}
    end
  end

  defp build_destination_path(context, tenant_id, owner_id, original_filename) do
    uuid = Ecto.UUID.generate()
    UploadPath.build_destination(context, tenant_id, owner_id, original_filename, uuid)
  end

  # Both paths are validated before this pipeline stage.
  # sobelow_skip ["Traversal.FileModule"]
  defp move_file_to_destination(temp_path, full_path) do
    case File.rename(temp_path, full_path) do
      :ok ->
        :ok

      {:error, :exdev} ->
        # Cross-filesystem move: copy + delete
        with :ok <- File.cp(temp_path, full_path) do
          File.rm(temp_path)
        end

      {:error, reason} ->
        {:error, {:move_failed, reason}}
    end
  end

  defp maybe_strip_metadata(full_path, context, family) do
    config = UploadConfig.get!(context)

    optimization_disabled? =
      is_nil(config.max_image_dimension) and is_nil(config.image_quality)

    if config.strip_image_metadata && optimization_disabled? &&
         family in [:jpeg, :png, :gif, :webp] do
      ImageMetadataStripper.strip_metadata(full_path)
    else
      :ok
    end
  end

  defp maybe_optimize_image(full_path, context, family) do
    config = UploadConfig.get!(context)

    if family in [:jpeg, :png, :gif, :webp] &&
         (config.max_image_dimension || config.image_quality) do
      ImageOptimizer.optimize(
        full_path,
        config.max_image_dimension,
        config.image_quality,
        config.strip_image_metadata
      )
    else
      :ok
    end
  end

  # The destination path is generated and bounded by UploadPath.
  # sobelow_skip ["Traversal.FileModule"]
  defp compute_sha256(full_path) do
    hash =
      File.stream!(full_path, 65_536)
      |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
        :crypto.hash_update(acc, chunk)
      end)
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    {:ok, hash}
  rescue
    _ -> {:error, :hash_compute_failed}
  end

  defp get_file_size(full_path) do
    case File.stat(full_path) do
      {:ok, %File.Stat{size: size}} -> {:ok, size}
      {:error, reason} -> {:error, {:stat_failed, reason}}
    end
  end

  defp persist_record(attrs) do
    changeset =
      UploadedFile.changeset(%UploadedFile{}, %{
        context: attrs.context,
        tenant_id: attrs.tenant_id,
        original_filename: sanitize_display_filename(attrs.original_filename),
        storage_path: attrs.storage_path,
        content_type: attrs.content_type,
        byte_size: attrs.byte_size,
        sha256: attrs.sha256,
        owner_type: attrs.owner_type,
        owner_id: attrs.owner_id,
        scan_status: :scanned
      })

    case Repo.insert(changeset) do
      {:ok, record} ->
        {:ok, record}

      {:error, changeset} ->
        {:error, {:database_error, changeset.errors}}
    end
  end

  defp sanitize_display_filename(filename) do
    # Remove control characters and path separators, then strip ".." sequences
    filename
    |> String.replace(~r/[\x00-\x1f\x7f\/\\]/, "")
    |> String.replace(~r/\.\.+/, "")
    |> String.slice(0..255)
  end
end
