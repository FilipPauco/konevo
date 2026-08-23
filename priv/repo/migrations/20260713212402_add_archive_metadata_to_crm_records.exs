defmodule Konevo.Repo.Migrations.AddArchiveMetadataToCrmRecords do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      add :archived_at, :utc_datetime
      add :archived_by_id, references(:users, on_delete: :nilify_all)
      add :archive_reason, :string
    end

    alter table(:contacts) do
      add :archived_at, :utc_datetime
      add :archived_by_id, references(:users, on_delete: :nilify_all)
      add :archive_reason, :string
    end

    alter table(:deals) do
      add :archived_at, :utc_datetime
      add :archived_by_id, references(:users, on_delete: :nilify_all)
      add :archive_reason, :string
    end

    alter table(:tasks) do
      add :archived_at, :utc_datetime
      add :archived_by_id, references(:users, on_delete: :nilify_all)
      add :archive_reason, :string
    end

    alter table(:memberships) do
      add :archived_at, :utc_datetime
      add :archived_by_id, references(:users, on_delete: :nilify_all)
      add :archive_reason, :string
    end

    create index(:companies, [:organization_id, :archived_at])
    create index(:contacts, [:organization_id, :archived_at])
    create index(:deals, [:organization_id, :archived_at])
    create index(:tasks, [:organization_id, :archived_at])
    create index(:memberships, [:organization_id, :archived_at])
  end
end
