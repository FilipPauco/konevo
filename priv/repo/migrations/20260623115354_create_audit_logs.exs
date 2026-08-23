defmodule Konevo.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :resource_type, :string
      add :resource_id, :integer
      add :metadata, :map, default: %{}
      add :ip_address, :string

      add :inserted_at, :utc_datetime, null: false
    end

    create index(:audit_logs, [:organization_id])
    create index(:audit_logs, [:actor_id])
    create index(:audit_logs, [:resource_type, :resource_id])
    create index(:audit_logs, [:action])
  end
end
