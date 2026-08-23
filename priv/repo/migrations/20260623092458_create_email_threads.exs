defmodule Konevo.Repo.Migrations.CreateEmailThreads do
  use Ecto.Migration

  def change do
    create table(:email_threads) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :nilify_all)
      add :deal_id, references(:deals, on_delete: :nilify_all)
      add :thread_id_gmail, :string
      add :thread_id_outlook, :string
      add :subject, :string, null: false
      add :category, :string
      add :snippet, :text
      add :is_unresolved, :boolean, default: true, null: false
      add :is_archived, :boolean, default: false, null: false
      add :revenue_at_risk, :decimal, precision: 15, scale: 2
      add :last_activity_at, :utc_datetime
      add :last_inbound_at, :utc_datetime
      add :participants, {:array, :string}, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:email_threads, [:organization_id])
    create index(:email_threads, [:contact_id])
    create index(:email_threads, [:deal_id])
    create index(:email_threads, [:is_unresolved])
    create index(:email_threads, [:category])
    create index(:email_threads, [:last_inbound_at])

    create unique_index(:email_threads, [:organization_id, :thread_id_gmail],
             where: "thread_id_gmail IS NOT NULL",
             name: :email_threads_org_gmail_thread_id_unique
           )

    create unique_index(:email_threads, [:organization_id, :thread_id_outlook],
             where: "thread_id_outlook IS NOT NULL",
             name: :email_threads_org_outlook_thread_id_unique
           )
  end
end
