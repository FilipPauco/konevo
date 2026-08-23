defmodule Konevo.Repo.Migrations.AddOrganizationIdToResources do
  use Ecto.Migration

  def change do
    # Add organization_id nullable first (safe for existing rows)
    alter table(:contacts) do
      add :organization_id, references(:organizations, on_delete: :delete_all)
    end

    alter table(:companies) do
      add :organization_id, references(:organizations, on_delete: :delete_all)
    end

    create index(:contacts, [:organization_id])
    create index(:companies, [:organization_id])
  end
end
