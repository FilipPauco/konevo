defmodule Konevo.Uploads.UploadConfig do
  @moduledoc """
  Central configuration for all upload contexts.

  Each context specifies:
  - storage_subdir: subdirectory under uploads root
  - allowed_extensions: list of allowed file extensions (with dot)
  - allowed_mimes: list of allowed MIME types
  - type_families: list of type families (for content sniffing)
  - max_file_size: maximum file size in bytes
  - max_entries: maximum number of entries per upload
  - strip_image_metadata: whether to strip EXIF/metadata from images
  - max_image_dimension: maximum pixel dimension (longest edge, nil = no limit)
  - image_quality: compression quality for lossy formats (1-100, nil = no resize)
  """

  # Type families for content sniffing
  @image_families [:jpeg, :png, :gif, :webp]
  @video_families [:mp4, :webm, :mov]
  @audio_families [:mp3, :wav, :ogg]
  @document_families [:pdf, :doc, :docx, :ppt, :pptx, :xls, :xlsx, :csv]

  @image_ext [".jpg", ".jpeg", ".png", ".gif", ".webp"]
  @image_mime ["image/jpeg", "image/png", "image/gif", "image/webp"]

  @video_ext [".mp4", ".webm", ".mov"]
  @video_mime ["video/mp4", "video/webm", "video/quicktime"]

  @audio_ext [".mp3", ".wav", ".ogg"]
  @audio_mime ["audio/mpeg", "audio/wav", "audio/ogg"]

  @document_ext [".pdf", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx", ".csv"]
  @document_mime [
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-powerpoint",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "text/csv"
  ]

  @configs %{
    avatar: %{
      storage_subdir: "avatars",
      allowed_extensions: @image_ext,
      allowed_mimes: @image_mime,
      type_families: @image_families,
      max_file_size: 5 * 1024 * 1024,
      max_entries: 1,
      strip_image_metadata: true,
      max_image_dimension: 512,
      image_quality: 85
    },
    document: %{
      storage_subdir: "documents",
      allowed_extensions: @document_ext,
      allowed_mimes: @document_mime,
      type_families: @document_families,
      max_file_size: 25 * 1024 * 1024,
      max_entries: 5,
      strip_image_metadata: false,
      max_image_dimension: nil,
      image_quality: nil
    },
    post_media: %{
      storage_subdir: "post_media",
      allowed_extensions: @image_ext ++ @video_ext ++ @audio_ext,
      allowed_mimes: @image_mime ++ @video_mime ++ @audio_mime,
      type_families: @image_families ++ @video_families ++ @audio_families,
      max_file_size: 500 * 1024 * 1024,
      max_entries: 10,
      strip_image_metadata: true,
      max_image_dimension: 2000,
      image_quality: 85
    },
    mixed_attachment: %{
      storage_subdir: "attachments",
      allowed_extensions: @image_ext ++ @video_ext ++ @audio_ext ++ @document_ext,
      allowed_mimes: @image_mime ++ @video_mime ++ @audio_mime ++ @document_mime,
      type_families: @image_families ++ @video_families ++ @audio_families ++ @document_families,
      max_file_size: 100 * 1024 * 1024,
      max_entries: 10,
      strip_image_metadata: true,
      max_image_dimension: 1600,
      image_quality: 85
    }
  }

  @doc """
  Get configuration for a context atom.
  Raises ArgumentError if context is not known.
  """
  def get!(context) when is_atom(context) do
    Map.fetch!(@configs, context)
  rescue
    KeyError ->
      reraise ArgumentError,
              [message: "Unknown upload context: #{inspect(context)}"],
              __STACKTRACE__
  end

  @doc """
  List all available contexts.
  """
  def contexts do
    Map.keys(@configs)
  end

  @doc """
  Safely cast a string context to an atom, preventing atom table exhaustion.
  Returns {:ok, atom} or {:error, :invalid_context}.
  """
  def cast_context(context_str) when is_binary(context_str) do
    context_atom = String.to_existing_atom(context_str)

    if context_atom in contexts() do
      {:ok, context_atom}
    else
      {:error, :invalid_context}
    end
  rescue
    ArgumentError ->
      # String.to_existing_atom raises if atom doesn't exist
      {:error, :invalid_context}
  end

  @doc """
  Check if an extension is allowed in any upload context.
  Used to catch completely unknown/dangerous extensions before context-specific MIME validation.
  Extension should include the dot (e.g., ".jpg").
  """
  def globally_allowed_extension?(extension) when is_binary(extension) do
    ext = String.downcase(extension)
    ext in (@image_ext ++ @video_ext ++ @audio_ext ++ @document_ext)
  end

  @doc """
  Validate an extension is in the allowed list for a context.
  Extension should include the dot (e.g., ".jpg").
  """
  def extension_allowed?(context, extension) when is_atom(context) and is_binary(extension) do
    config = get!(context)
    String.downcase(extension) in config.allowed_extensions
  end

  @doc """
  Validate a MIME type is in the allowed list for a context.
  """
  def mime_allowed?(context, mime_type) when is_atom(context) and is_binary(mime_type) do
    config = get!(context)
    String.downcase(mime_type) in config.allowed_mimes
  end

  @doc """
  Validate file size is within limit for a context.
  """
  def size_valid?(context, byte_size) when is_atom(context) and is_integer(byte_size) do
    config = get!(context)
    byte_size <= config.max_file_size
  end

  @doc """
  Get uploads directory from app config or use default.
  """
  def uploads_root do
    Application.get_env(:konevo, :uploads_root, Path.join(File.cwd!(), "priv/uploads"))
  end
end
