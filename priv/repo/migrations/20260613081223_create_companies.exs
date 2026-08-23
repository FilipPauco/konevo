defmodule Konevo.Repo.Migrations.CreateCompanies do
  use Ecto.Migration

  def change do
    create table(:companies) do
      add :name, :string, null: false
      add :website, :string
      add :industry, :string
      add :phone, :string
      add :notes, :text
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:companies, [:user_id])
  end
end
