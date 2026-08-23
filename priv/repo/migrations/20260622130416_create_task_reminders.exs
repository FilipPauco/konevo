defmodule Konevo.Repo.Migrations.CreateTaskReminders do
  use Ecto.Migration

  def change do
    create table(:task_reminders) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :remind_at, :utc_datetime, null: false
      add :reminder_type, :string, null: false
      add :notified_at, :utc_datetime

      add :inserted_at, :utc_datetime, null: false
    end

    create index(:task_reminders, [:task_id])
    create index(:task_reminders, [:remind_at])
  end
end
