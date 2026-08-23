defmodule Konevo.Repo.Migrations.CreateAutomationTaskApprovals do
  use Ecto.Migration

  def change do
    create table(:automation_task_approvals) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :sequence_id, references(:automation_sequences, on_delete: :nilify_all)
      add :email_id, references(:emails, on_delete: :delete_all), null: false
      add :email_thread_id, references(:email_threads, on_delete: :nilify_all)
      add :contact_id, references(:contacts, on_delete: :nilify_all)
      add :company_id, references(:companies, on_delete: :nilify_all)
      add :title, :string, null: false
      add :description, :text
      add :due_date, :utc_datetime, null: false
      add :priority, :string, null: false, default: "normal"
      add :confidence, :float
      add :status, :string, null: false, default: "pending"
      add :approved_at, :utc_datetime
      add :approved_by_id, references(:users, on_delete: :nilify_all)
      add :created_task_id, references(:tasks, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:automation_task_approvals, [:organization_id, :status])
    create index(:automation_task_approvals, [:email_id])
    create index(:automation_task_approvals, [:email_thread_id])
    create index(:automation_task_approvals, [:created_task_id])
  end
end
