defmodule Konevo.Repo.Migrations.CreateConsents do
  use Ecto.Migration

  def change do
    create table(:consents) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :channel, :string, null: false
      add :status, :string, null: false, default: "granted"
      add :source, :string, null: false, default: "manual"
      add :ip_address, :string
      add :granted_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:consents, [:organization_id, :contact_id, :channel])
    create index(:consents, [:contact_id])
    create index(:consents, [:status])
  end
end
