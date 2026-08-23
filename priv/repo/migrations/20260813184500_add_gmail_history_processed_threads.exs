defmodule Konevo.Repo.Migrations.AddGmailHistoryProcessedThreads do
  use Ecto.Migration

  def change do
    alter table(:email_integrations) do
      add :history_processed_threads, :integer, default: 0, null: false
    end
  end
end
