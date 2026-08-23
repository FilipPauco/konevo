defmodule Konevo.Repo.Migrations.RenameDealsViewModeToCompaniesViewMode do
  use Ecto.Migration

  def change do
    rename table(:users), :deals_view_mode, to: :companies_view_mode
  end
end
