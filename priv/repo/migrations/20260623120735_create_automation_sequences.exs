defmodule Konevo.Repo.Migrations.CreateAutomationSequences do
  use Ecto.Migration

  def change do
    create table(:automation_sequences) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :name, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "draft"
      add :trigger_type, :string, null: false
      add :trigger_config, :map, default: %{}
      add :enrollment_limit, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:automation_sequences, [:organization_id])
    create index(:automation_sequences, [:status])
    create index(:automation_sequences, [:trigger_type])
  end
end
