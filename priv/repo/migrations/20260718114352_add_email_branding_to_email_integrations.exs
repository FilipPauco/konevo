defmodule Konevo.Repo.Migrations.AddEmailBrandingToEmailIntegrations do
  use Ecto.Migration

  def change do
    alter table(:email_integrations) do
      add :signature_html, :text
      add :signature_text, :text
      add :footer_html, :text
      add :footer_text, :text
      add :branding_image_url, :string
      add :branding_enabled, :boolean, default: true, null: false
    end
  end
end
