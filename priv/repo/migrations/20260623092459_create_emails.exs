defmodule Konevo.Repo.Migrations.CreateEmails do
  use Ecto.Migration

  def change do
    create table(:emails) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :thread_id, references(:email_threads, on_delete: :delete_all), null: false
      add :message_id, :string, null: false
      add :from, :string, null: false
      add :to, {:array, :string}, null: false, default: []
      add :cc, {:array, :string}, default: []
      add :bcc, {:array, :string}, default: []
      add :subject, :string
      add :body, :text
      add :html_body, :text
      add :headers, :map
      add :received_at, :utc_datetime, null: false
      add :is_inbound, :boolean, null: false

      add :inserted_at, :utc_datetime, null: false
    end

    create index(:emails, [:thread_id])
    create index(:emails, [:organization_id])
    create index(:emails, [:received_at])
    create unique_index(:emails, [:message_id])
  end
end
