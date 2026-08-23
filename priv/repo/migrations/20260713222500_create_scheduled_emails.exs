defmodule Konevo.Repo.Migrations.CreateScheduledEmails do
  use Ecto.Migration

  def change do
    create table(:scheduled_emails) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :scheduled_by_id, references(:users, on_delete: :nilify_all)
      add :email_thread_id, references(:email_threads, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :to, {:array, :string}, null: false, default: []
      add :cc, {:array, :string}, null: false, default: []
      add :bcc, {:array, :string}, null: false, default: []
      add :subject, :string
      add :body, :text, null: false
      add :in_reply_to, :string
      add :gmail_thread_id, :string
      add :scheduled_at, :utc_datetime, null: false
      add :sent_at, :utc_datetime
      add :cancelled_at, :utc_datetime
      add :failed_at, :utc_datetime
      add :status, :string, null: false, default: "pending"
      add :external_message_id, :string
      add :failure_reason, :text
      add :oban_job_id, references(:oban_jobs, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:scheduled_emails, [:organization_id])
    create index(:scheduled_emails, [:email_thread_id])
    create index(:scheduled_emails, [:scheduled_by_id])
    create index(:scheduled_emails, [:status])
    create index(:scheduled_emails, [:scheduled_at])
    create index(:scheduled_emails, [:oban_job_id])
  end
end
