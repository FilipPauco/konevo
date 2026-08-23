defmodule Konevo.Repo.Migrations.CreateDeals do
  use Ecto.Migration

  def change do
    create table(:deals) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :restrict), null: false
      add :stage_id, references(:deal_stages, on_delete: :restrict), null: false
      add :owner_id, references(:users, on_delete: :nilify_all)
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :title, :string, null: false
      add :description, :text
      add :value, :decimal, null: false, precision: 15, scale: 2
      add :currency, :string, default: "EUR", null: false
      add :expected_close_date, :date
      add :probability, :integer
      add :next_action, :text
      add :next_action_due_date, :utc_datetime
      add :source, :string
      add :reason_lost, :text
      add :closed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:deals, [:organization_id])
    create index(:deals, [:contact_id])
    create index(:deals, [:stage_id])
    create index(:deals, [:owner_id])
  end
end
