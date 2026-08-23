defmodule Konevo.Repo.Migrations.RemoveGoogleAiProviderSettings do
  use Ecto.Migration

  def up do
    execute("DELETE FROM ai_provider_settings WHERE provider = 'google_ai'")
  end

  def down, do: :ok
end
