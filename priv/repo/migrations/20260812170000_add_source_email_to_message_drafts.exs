defmodule Konevo.Repo.Migrations.AddSourceEmailToMessageDrafts do
  use Ecto.Migration

  def change do
    alter table(:message_drafts) do
      add :source_email_id, references(:emails, on_delete: :nilify_all)
    end

    create index(:message_drafts, [:organization_id, :source_email_id],
             unique: true,
             where: "source_email_id IS NOT NULL"
           )
  end
end
