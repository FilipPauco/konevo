defmodule Konevo.Repo.Migrations.NormalizeExistingGmailHistoryImportCounts do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE email_integrations
    SET history_processed_threads = history_imported_threads,
        history_imported_threads = 0
    WHERE history_import_status = 'completed'
      AND history_processed_threads = 0
      AND history_imported_threads > 0
    """)
  end

  def down do
    :ok
  end
end
