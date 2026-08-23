defmodule Konevo.Repo.Migrations.ChangeDefaultAiPreferenceLanguageToAuto do
  use Ecto.Migration

  def up do
    alter table(:ai_preferences) do
      modify :language, :string, default: "auto", null: false
    end
  end

  def down do
    alter table(:ai_preferences) do
      modify :language, :string, default: "English", null: false
    end
  end
end
