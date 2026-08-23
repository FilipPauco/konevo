defmodule Konevo.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    create table(:organizations) do
      add :name, :string, null: false
      add :slug, :citext, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organizations, [:slug])
  end
end
