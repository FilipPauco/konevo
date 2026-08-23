defmodule KonevoWeb.Seo do
  @moduledoc false

  @site_name "Konevo"
  @default_description "Self-hosted AI CRM for Gmail: turn customer email into contacts, tasks, and reviewable follow-ups."

  def default_description, do: @default_description

  def page_url(path) when is_binary(path) do
    KonevoWeb.Endpoint.url()
    |> URI.merge(path)
    |> to_string()
  end

  def social_image_url, do: page_url("/images/landing_small.png")

  def software_application_json_ld do
    %{
      "@context" => "https://schema.org",
      "@type" => "SoftwareApplication",
      "applicationCategory" => "BusinessApplication",
      "description" => @default_description,
      "image" => social_image_url(),
      "name" => @site_name,
      "operatingSystem" => "Web",
      "url" => page_url("/")
    }
    |> Jason.encode!()
  end
end
