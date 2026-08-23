defmodule Konevo.Uploads.UploadedFile do
  @moduledoc """
  Schema for tracking uploaded files.

  The database record is the source of truth for what a file is and who may access it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "uploaded_files" do
    field :context, Ecto.Enum, values: [:avatar, :document, :post_media, :mixed_attachment]
    field :tenant_id, :string
    field :original_filename, :string
    field :storage_path, :string
    field :content_type, :string
    field :byte_size, :integer
    field :sha256, :string
    field :owner_type, :string
    field :owner_id, :string
    field :scan_status, Ecto.Enum, values: [:pending, :scanned, :quarantined]
    field :deleted_at, :utc_datetime
    field :delete_failed_at, :utc_datetime
    field :delete_error, :string

    timestamps()
  end

  @doc """
  Changeset for creating a new uploaded file record.
  """
  def changeset(file, attrs) do
    file
    |> cast(attrs, [
      :context,
      :tenant_id,
      :original_filename,
      :storage_path,
      :content_type,
      :byte_size,
      :sha256,
      :owner_type,
      :owner_id,
      :scan_status
    ])
    |> validate_required([
      :context,
      :tenant_id,
      :original_filename,
      :storage_path,
      :content_type,
      :byte_size,
      :sha256,
      :owner_type,
      :owner_id,
      :scan_status
    ])
    |> validate_inclusion(:scan_status, [:pending, :scanned, :quarantined])
    |> unique_constraint(:storage_path)
  end
end
