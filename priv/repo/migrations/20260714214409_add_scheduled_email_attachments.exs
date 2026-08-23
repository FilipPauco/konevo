defmodule Konevo.Repo.Migrations.AddScheduledEmailAttachments do
  use Ecto.Migration

  def change do
    alter table(:scheduled_emails) do
      add(:attachment_owner_id, :string)
      add(:attachment_ids, {:array, :integer}, null: false, default: [])
    end
  end
end
