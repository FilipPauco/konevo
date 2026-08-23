defmodule Konevo.Uploads.UploadPath do
  @moduledoc """
  Secure path resolution for uploaded files.

  Storage layout (tenant-first for security):
    <uploads_root>/<context_subdir>/<tenant_id>/<owner_id>/<uuid>.<ext>

  All path components (tenant_id, owner_id) must come from authenticated context,
  never from user input.
  """

  alias Konevo.Uploads.{PathTraversalError, UploadConfig}

  @id_pattern ~r/^[a-zA-Z0-9\-]{1,64}$/

  @doc """
  Build a safe destination path for an uploaded file.

  Takes:
  - context: upload context atom
  - tenant_id: from authenticated session (must be valid ID)
  - owner_id: from authenticated session (must be valid ID)
  - filename: original filename (used for extension only)
  - uuid: generated UUID for the file

  Returns the relative path from uploads root (e.g., "avatars/tenant-123/user-456/uuid.jpg")

  Raises PathTraversalError if any validation fails.
  """
  def build_destination(context, tenant_id, owner_id, filename, uuid)
      when is_atom(context) and is_binary(tenant_id) and is_binary(owner_id) and
             is_binary(filename) and is_binary(uuid) do
    # Validate and sanitize all components
    sanitized_tenant = sanitize_scope_segment(tenant_id)
    sanitized_owner = sanitize_scope_segment(owner_id)
    extension = extract_and_validate_extension(filename)

    config = UploadConfig.get!(context)
    subdir = config.storage_subdir

    # Build relative path
    relative = Path.join([subdir, sanitized_tenant, sanitized_owner, "#{uuid}#{extension}"])

    # Full path
    full_path = Path.join(UploadConfig.uploads_root(), relative)

    # Final sanity check: ensure path hasn't escaped uploads root
    assert_within_root!(full_path)

    relative
  end

  @doc """
  Expand a relative upload path to full filesystem path and validate containment.
  """
  def expand(relative_path) when is_binary(relative_path) do
    uploads_root = UploadConfig.uploads_root()
    full_path = Path.join(uploads_root, relative_path)
    assert_within_root!(full_path)
    full_path
  end

  @doc """
  Resolve a stored upload path for serving after validating root and tenant containment.
  """
  def resolve_for_serving(relative_path, expected_tenant_id) do
    full_path = expand(relative_path)
    :ok = assert_tenant_segment!(relative_path, expected_tenant_id)
    {:ok, full_path}
  rescue
    PathTraversalError -> {:error, :invalid_storage_path}
  end

  @doc """
  Sanitize and validate a scope segment (tenant_id or owner_id).

  Enforces: alphanumeric + hyphens only, max 64 chars, not empty.
  Raises PathTraversalError on invalid input.
  """
  def sanitize_scope_segment(segment) when is_binary(segment) do
    if Regex.match?(@id_pattern, segment) do
      segment
    else
      raise PathTraversalError,
        message:
          "Invalid scope segment: #{inspect(segment)}. Must be 1-64 alphanumeric/hyphen characters."
    end
  end

  @doc """
  Extract and validate the file extension.

  Ensures extension matches allowed pattern: ^\\.[a-z0-9]{1,5}$
  Raises PathTraversalError if invalid.
  """
  def extract_and_validate_extension(filename) when is_binary(filename) do
    # Get the last extension
    case Path.extname(filename) |> String.downcase() do
      ext when byte_size(ext) in 2..6 ->
        # Reject double extensions (e.g., file.tar.gz)
        stem = Path.rootname(filename)

        if Path.extname(stem) != "" do
          raise PathTraversalError,
            message: "Multiple file extensions detected: #{inspect(filename)}"
        end

        # Validate format
        if Regex.match?(~r/^\.[a-z0-9]{1,5}$/, ext) do
          ext
        else
          raise PathTraversalError,
            message: "Invalid file extension: #{inspect(ext)}"
        end

      ext ->
        raise PathTraversalError,
          message: "Invalid file extension: #{inspect(ext)}. Must be 1-5 chars."
    end
  end

  @doc """
  Defense-in-depth check: verify a path is within the uploads root.

  Expands both paths and verifies the target is a child of the root.
  Raises PathTraversalError if traversal attempt is detected.
  """
  def assert_within_root!(full_path) when is_binary(full_path) do
    assert_within_directory!(full_path, UploadConfig.uploads_root())
  end

  @doc """
  Verify a path is contained by a trusted directory.

  Raises PathTraversalError when the expanded path escapes the directory.
  """
  def assert_within_directory!(full_path, trusted_directory)
      when is_binary(full_path) and is_binary(trusted_directory) do
    # Reject any path containing traversal sequences
    path_parts = String.split(full_path, ["/", "\\"])

    if ".." in path_parts do
      raise PathTraversalError,
        message: "Path traversal detected: path contains '..' component"
    end

    expanded_root = Path.expand(trusted_directory)
    expanded_path = Path.expand(full_path)

    relative_to_root = Path.relative_to(expanded_path, expanded_root)

    if within_root?(relative_to_root) do
      expanded_path
    else
      raise PathTraversalError,
        message:
          "Path traversal detected: #{inspect(expanded_path)} is outside #{inspect(expanded_root)}"
    end
  end

  defp within_root?(relative_path) do
    Path.type(relative_path) == :relative and
      relative_path != ".." and
      not String.starts_with?(relative_path, ["../", "..\\"])
  end

  @doc """
  Extract tenant_id from a storage path.

  Assumes path format: <subdir>/<tenant_id>/<owner_id>/<uuid>.<ext>
  Returns the tenant_id segment or nil if extraction fails.
  """
  def extract_tenant_id(storage_path) when is_binary(storage_path) do
    parts = String.split(storage_path, "/")

    case parts do
      [_subdir, tenant_id, _owner_id, _file] ->
        tenant_id

      _ ->
        nil
    end
  end

  @doc """
  Verify the tenant_id in a storage path matches the expected tenant.

  This is a defense-in-depth check at serve time to catch any drift.
  """
  def assert_tenant_segment!(storage_path, expected_tenant_id) do
    case extract_tenant_id(storage_path) do
      ^expected_tenant_id ->
        :ok

      actual_tenant_id ->
        raise PathTraversalError,
          message:
            "Tenant mismatch in storage path. Expected: #{inspect(expected_tenant_id)}, Got: #{inspect(actual_tenant_id)}"
    end
  end

  @doc """
  Create the directory structure for a file if it doesn't exist.

  Takes the relative path and creates all parent directories.
  """
  # sobelow_skip ["Traversal.FileModule"]
  def ensure_directory!(relative_path) when is_binary(relative_path) do
    full_path = expand(relative_path)
    dir_path = Path.dirname(full_path)

    case File.mkdir_p(dir_path) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to create directory #{dir_path}: #{inspect(reason)}"
    end
  end
end
