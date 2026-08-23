defmodule Konevo.Repo.Migrations.CreateContactDedupes do
  use Ecto.Migration

  def change do
    create table(:contact_dedupes) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :primary_contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :duplicate_contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :merged_by_id, references(:users, on_delete: :nilify_all)
      add :merge_notes, :text
      add :merged_at, :utc_datetime

      add :inserted_at, :utc_datetime, null: false
    end

    create index(:contact_dedupes, [:organization_id])
    create index(:contact_dedupes, [:primary_contact_id])
    create index(:contact_dedupes, [:duplicate_contact_id])
  end
end
