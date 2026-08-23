defmodule Konevo.Repo.Migrations.CreateAutomationRules do
  use Ecto.Migration

  def change do
    create table(:automation_rules) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :sequence_id, references(:automation_sequences, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0
      add :action_type, :string, null: false
      add :action_config, :map, default: %{}
      add :delay_seconds, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:automation_rules, [:sequence_id])
    create index(:automation_rules, [:organization_id])
    create index(:automation_rules, [:sequence_id, :position])
  end
end
