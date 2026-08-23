defmodule Konevo.Repo.Migrations.CreateDealStages do
  use Ecto.Migration

  def change do
    create table(:deal_stages) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0
      add :color, :string
      add :is_final, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:deal_stages, [:organization_id])
    create unique_index(:deal_stages, [:organization_id, :position])
  end
end
