defmodule Konevo.Repo.Migrations.CreateAiProviderSettings do
  use Ecto.Migration

  def change do
    create table(:ai_provider_settings) do
      add :provider, :string, null: false
      add :encrypted_api_key, :text
      add :api_key_last4, :string
      add :monthly_budget, :decimal, precision: 12, scale: 2
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_provider_settings, [:organization_id, :user_id, :provider])
    create index(:ai_provider_settings, [:organization_id, :provider])
  end
end
