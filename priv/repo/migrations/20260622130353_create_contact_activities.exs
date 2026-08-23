defmodule Konevo.Repo.Migrations.CreateContactActivities do
  use Ecto.Migration

  def change do
    create table(:contact_activities) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :activity_type, :string, null: false
      add :activity_date, :utc_datetime, null: false
      add :related_resource_type, :string
      add :related_resource_id, :bigint
      add :summary, :text

      add :inserted_at, :utc_datetime, null: false
    end

    create index(:contact_activities, [:contact_id])
    create index(:contact_activities, [:organization_id])
    create index(:contact_activities, [:activity_date])
  end
end
