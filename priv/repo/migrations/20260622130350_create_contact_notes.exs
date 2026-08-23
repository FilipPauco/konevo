defmodule Konevo.Repo.Migrations.CreateContactNotes do
  use Ecto.Migration

  def change do
    create table(:contact_notes) do
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :body, :text, null: false
      add :is_internal, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:contact_notes, [:contact_id])
    create index(:contact_notes, [:organization_id])
  end
end
