defmodule Konevo.Repo.Migrations.CreateSuppressionLists do
  use Ecto.Migration

  def change do
    create table(:suppression_lists) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :channel, :string, null: false
      add :value, :string, null: false
      add :reason, :string, null: false, default: "unsubscribed"
      add :source_message_id, references(:messages_sent, on_delete: :nilify_all)

      add :inserted_at, :utc_datetime, null: false
    end

    create unique_index(:suppression_lists, [:organization_id, :channel, :value])
    create index(:suppression_lists, [:organization_id])
    create index(:suppression_lists, [:value])
  end
end
