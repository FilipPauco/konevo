defmodule Konevo.Repo.Migrations.AddViewModesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :contacts_view_mode, :string, default: "table", null: false
      add :deals_view_mode, :string, default: "table", null: false
    end
  end
end
