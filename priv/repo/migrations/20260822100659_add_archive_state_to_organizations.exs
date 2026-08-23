defmodule Konevo.Repo.Migrations.AddArchiveStateToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :archived_at, :utc_datetime
    end

    create index(:organizations, [:archived_at])
  end
end
