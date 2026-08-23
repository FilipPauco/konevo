defmodule Konevo.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :nilify_all)
      add :deal_id, references(:deals, on_delete: :nilify_all)
      add :assigned_to_id, references(:users, on_delete: :nilify_all)
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :completed_by_id, references(:users, on_delete: :nilify_all)
      add :title, :string, null: false
      add :description, :text
      add :due_date, :utc_datetime, null: false
      add :status, :string, null: false, default: "open"
      add :priority, :string, null: false, default: "normal"
      add :reminder_sent_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:organization_id])
    create index(:tasks, [:contact_id])
    create index(:tasks, [:deal_id])
    create index(:tasks, [:assigned_to_id])
    create index(:tasks, [:due_date])
    create index(:tasks, [:status])
  end
end
