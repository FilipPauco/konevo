defmodule Konevo.Repo.Migrations.AddApprovalExpiryDaysToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :approval_expiry_days, :integer, null: false, default: 7
    end
  end
end
