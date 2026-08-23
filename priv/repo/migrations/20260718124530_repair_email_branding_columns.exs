defmodule Konevo.Repo.Migrations.RepairEmailBrandingColumns do
  use Ecto.Migration

  def up do
    alter table(:email_integrations) do
      add_if_not_exists :signature_html, :text
      add_if_not_exists :signature_text, :text
      add_if_not_exists :footer_html, :text
      add_if_not_exists :footer_text, :text
      add_if_not_exists :branding_image_url, :string
      add_if_not_exists :branding_enabled, :boolean, default: true, null: false
    end
  end

  def down do
    :ok
  end
end
