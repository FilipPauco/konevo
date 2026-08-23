defmodule Konevo.Repo.Migrations.KeepOnlyEmailSignatureHtml do
  use Ecto.Migration

  def up do
    alter table(:email_integrations) do
      add_if_not_exists :signature_html, :text
      remove_if_exists :signature_text, :text
      remove_if_exists :footer_html, :text
      remove_if_exists :footer_text, :text
      remove_if_exists :branding_image_url, :string
      remove_if_exists :branding_enabled, :boolean
    end
  end

  def down do
    :ok
  end
end
