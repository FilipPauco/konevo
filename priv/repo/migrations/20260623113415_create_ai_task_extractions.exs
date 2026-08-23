defmodule Konevo.Repo.Migrations.CreateAiTaskExtractions do
  use Ecto.Migration

  def change do
    create table(:ai_task_extractions) do
      add :email_id, references(:emails, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :extracted_tasks, {:array, :map}, null: false, default: []
      add :extraction_confidence, :float, null: false
      add :model_used, :string, null: false

      add :inserted_at, :utc_datetime, null: false
    end

    create index(:ai_task_extractions, [:email_id])
    create index(:ai_task_extractions, [:organization_id])
  end
end
