defmodule Konevo.Repo.Migrations.CreateUploadedFiles do
  use Ecto.Migration

  def change do
    create table(:uploaded_files) do
      add :context, :string, null: false
      add :tenant_id, :string, null: false
      add :original_filename, :string, null: false
      add :storage_path, :string, null: false
      add :content_type, :string, null: false
      add :byte_size, :integer, null: false
      add :sha256, :string, null: false
      add :owner_type, :string, null: false
      add :owner_id, :string, null: false
      add :scan_status, :string, null: false, default: "scanned"

      timestamps()
    end

    # Indexes for common queries
    create index(:uploaded_files, [:tenant_id])
    create index(:uploaded_files, [:tenant_id, :context])
    create index(:uploaded_files, [:tenant_id, :owner_type, :owner_id])

    # Unique constraint on storage path (prevent duplicates)
    create unique_index(:uploaded_files, [:storage_path])
  end
end
