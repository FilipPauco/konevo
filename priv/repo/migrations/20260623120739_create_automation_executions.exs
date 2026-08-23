defmodule Konevo.Repo.Migrations.CreateAutomationExecutions do
  use Ecto.Migration

  def change do
    create table(:automation_executions) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :sequence_id, references(:automation_sequences, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :current_rule_id, references(:automation_rules, on_delete: :nilify_all)
      add :status, :string, null: false, default: "pending"
      add :enrolled_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime
      add :error_message, :text
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:automation_executions, [:organization_id])
    create index(:automation_executions, [:sequence_id])
    create index(:automation_executions, [:contact_id])
    create index(:automation_executions, [:status])

    # prevent duplicate active enrollments per (sequence, contact)
    create unique_index(:automation_executions, [:sequence_id, :contact_id],
             where: "status IN ('pending', 'running')",
             name: :automation_executions_active_unique
           )
  end
end
