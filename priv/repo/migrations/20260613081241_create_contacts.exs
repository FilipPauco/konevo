defmodule Konevo.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts) do
      add :first_name, :string, null: false
      add :last_name, :string
      add :email, :string
      add :phone, :string
      add :status, :string, null: false, default: "lead"
      add :notes, :text
      add :company_id, references(:companies, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:contacts, [:user_id])
    create index(:contacts, [:company_id])
  end
end
