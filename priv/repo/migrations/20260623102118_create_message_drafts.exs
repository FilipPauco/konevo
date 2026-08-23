defmodule Konevo.Repo.Migrations.CreateMessageDrafts do
  use Ecto.Migration

  def change do
    create table(:message_drafts) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :nilify_all)
      add :email_thread_id, references(:email_threads, on_delete: :nilify_all)
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :approved_by_id, references(:users, on_delete: :nilify_all)
      add :sent_message_id, references(:messages_sent, on_delete: :nilify_all)
      add :message_type, :string, null: false
      add :subject, :string
      add :body, :text, null: false
      add :ai_generated, :boolean, null: false, default: false
      add :ai_model_used, :string
      add :ai_confidence, :float
      add :tone_preset, :string
      add :status, :string, null: false, default: "pending"
      add :approved_at, :utc_datetime
      add :approval_changes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:message_drafts, [:organization_id])
    create index(:message_drafts, [:contact_id])
    create index(:message_drafts, [:email_thread_id])
    create index(:message_drafts, [:status])
    create index(:message_drafts, [:ai_generated])
  end
end
