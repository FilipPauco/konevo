defmodule Konevo.Repo.Migrations.AddTwoFactorAuthToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :two_factor_secret, :string
      add :two_factor_last_used_at, :utc_datetime
    end
  end
end
