defmodule KonevoWeb.LegalController do
  use KonevoWeb, :controller

  alias KonevoWeb.Seo

  def privacy(conn, _params) do
    conn
    |> assign(:page_title, gettext("Privacy Policy — Konevo"))
    |> assign(:seo_description, gettext("Privacy Policy for the self-hosted Konevo CRM."))
    |> assign(:seo_robots, "index, follow")
    |> assign(:seo_url, Seo.page_url("/privacy"))
    |> render(:privacy)
  end

  def terms(conn, _params) do
    conn
    |> assign(:page_title, gettext("Terms of Use — Konevo"))
    |> assign(:seo_description, gettext("Terms of Use for the self-hosted Konevo CRM."))
    |> assign(:seo_robots, "index, follow")
    |> assign(:seo_url, Seo.page_url("/terms"))
    |> render(:terms)
  end
end
