defmodule Konevo.Repo.Migrations.CreateTenantInvitations do
  use Ecto.Migration

  def change do
    create table(:tenant_invitations) do
      add :email, :string, null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:tenant_invitations, [:token_hash])
    create unique_index(:tenant_invitations, [:organization_id])
    create index(:tenant_invitations, [:email])
  end
end
