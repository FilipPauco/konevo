defmodule Konevo.Repo.Migrations.CreateDealActivities do
  use Ecto.Migration

  def change do
    create table(:deal_activities) do
      add :deal_id, references(:deals, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :activity_type, :string, null: false
      add :old_value, :string
      add :new_value, :string

      add :inserted_at, :utc_datetime, null: false
    end

    create index(:deal_activities, [:deal_id])
  end
end
