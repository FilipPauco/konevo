defmodule Konevo.Tasks.TaskReminder do
  use Ecto.Schema
  import Ecto.Changeset

  @reminder_types [:on_day, :one_day_before, :three_days_before, :overdue_alert]

  schema "task_reminders" do
    field :remind_at, :utc_datetime
    field :reminder_type, Ecto.Enum, values: @reminder_types
    field :notified_at, :utc_datetime

    belongs_to :task, Konevo.Tasks.Task

    field :inserted_at, :utc_datetime, autogenerate: {DateTime, :utc_now, [:second]}
  end

  def reminder_types, do: @reminder_types

  @doc false
  def changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [:remind_at, :reminder_type, :notified_at])
    |> validate_required([:remind_at, :reminder_type])
  end
end
