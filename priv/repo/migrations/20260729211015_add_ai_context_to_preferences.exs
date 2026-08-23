defmodule Konevo.Repo.Migrations.AddAiContextToPreferences do
  use Ecto.Migration

  def change do
    alter table(:ai_preferences) do
      add :workspace_context, :text
      add :email_instructions, :text
    end
  end
end
