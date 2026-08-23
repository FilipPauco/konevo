defmodule Konevo.Repo.Migrations.AddLinkedinUrlsToContactsAndCompanies do
  use Ecto.Migration

  def change do
    alter table(:contacts) do
      add :linkedin_url, :string
    end

    alter table(:companies) do
      add :linkedin_url, :string
    end
  end
end
