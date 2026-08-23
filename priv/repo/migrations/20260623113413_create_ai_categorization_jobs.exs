defmodule Konevo.Repo.Migrations.CreateAiCategorizationJobs do
  use Ecto.Migration

  def change do
    create table(:ai_categorization_jobs) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :email_thread_id, references(:email_threads, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :result_category, :string
      add :confidence_score, :float
      add :error_message, :text
      add :processed_at, :utc_datetime

      add :inserted_at, :utc_datetime, null: false
    end

    create index(:ai_categorization_jobs, [:organization_id])
    create index(:ai_categorization_jobs, [:email_thread_id])
    create index(:ai_categorization_jobs, [:status])
  end
end
