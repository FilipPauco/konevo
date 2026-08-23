defmodule Konevo.Repo.Migrations.AddCrmInboxState do
  use Ecto.Migration

  def change do
    alter table(:email_threads) do
      add :is_favorite, :boolean, default: false, null: false
      add :read_at, :utc_datetime
      add :trashed_at, :utc_datetime
      add :last_outbound_at, :utc_datetime
      add :has_attachments, :boolean, default: false, null: false
    end

    alter table(:emails) do
      add :has_attachments, :boolean, default: false, null: false
    end

    alter table(:tasks) do
      add :source_email_id, references(:emails, on_delete: :nilify_all)
      add :source_thread_id, references(:email_threads, on_delete: :nilify_all)
    end

    create index(:email_threads, [:organization_id, :is_favorite])
    create index(:email_threads, [:organization_id, :trashed_at])
    create index(:email_threads, [:organization_id, :last_outbound_at])
    create index(:email_threads, [:organization_id, :has_attachments])
    create index(:tasks, [:source_email_id])
    create index(:tasks, [:source_thread_id])
  end
end
