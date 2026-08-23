defmodule Konevo.Repo.Migrations.AddUploadDeleteTracking do
  use Ecto.Migration

  def change do
    alter table(:uploaded_files) do
      add :deleted_at, :utc_datetime
      add :delete_failed_at, :utc_datetime
      add :delete_error, :string
    end

    create index(:uploaded_files, [:deleted_at])
    create index(:uploaded_files, [:delete_failed_at])
  end
end
