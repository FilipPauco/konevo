defmodule Konevo.Repo.Migrations.CreateMessagesSent do
  use Ecto.Migration

  def change do
    create table(:messages_sent) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :nilify_all)
      add :sent_by_id, references(:users, on_delete: :nilify_all)
      add :message_type, :string, null: false
      add :recipient, :string, null: false
      add :subject, :string
      add :body, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :sent_at, :utc_datetime
      add :opened_at, :utc_datetime
      add :clicked_at, :utc_datetime
      add :delivery_status, :string
      add :is_manual, :boolean, null: false, default: false
      add :is_automation, :boolean, null: false, default: false
      add :external_message_id, :string

      timestamps(type: :utc_datetime)
    end

    create index(:messages_sent, [:organization_id])
    create index(:messages_sent, [:contact_id])
    create index(:messages_sent, [:sent_by_id])
    create index(:messages_sent, [:status])
    create index(:messages_sent, [:message_type])
    create index(:messages_sent, [:sent_at])
  end
end
