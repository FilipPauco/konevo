defmodule Konevo.Repo.Migrations.CreateEmailIntegrations do
  use Ecto.Migration

  def change do
    create table(:email_integrations) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :email_address, :string, null: false
      add :access_token, :binary
      add :refresh_token, :binary
      add :token_expires_at, :utc_datetime
      add :is_primary, :boolean, default: false, null: false
      add :sync_enabled, :boolean, default: true, null: false
      add :last_sync_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:email_integrations, [:organization_id])
    create index(:email_integrations, [:user_id])
    create unique_index(:email_integrations, [:organization_id, :email_address])
  end
end
