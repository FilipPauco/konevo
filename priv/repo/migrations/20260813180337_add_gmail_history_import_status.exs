defmodule Konevo.Repo.Migrations.AddGmailHistoryImportStatus do
  use Ecto.Migration

  def change do
    alter table(:email_integrations) do
      add :history_import_status, :string, default: "idle", null: false
      add :history_import_started_at, :utc_datetime
      add :history_import_completed_at, :utc_datetime
      add :history_imported_threads, :integer, default: 0, null: false
      add :history_import_error, :string
    end
  end
end
