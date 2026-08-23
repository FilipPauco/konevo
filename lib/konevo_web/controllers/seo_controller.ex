defmodule KonevoWeb.SeoController do
  use KonevoWeb, :controller

  alias KonevoWeb.Seo

  def robots(conn, _params) do
    body = """
    User-agent: *
    Allow: /
    Disallow: /dashboard
    Disallow: /contacts
    Disallow: /companies
    Disallow: /deals
    Disallow: /inbox
    Disallow: /tasks
    Disallow: /automation
    Disallow: /calendar
    Disallow: /team
    Disallow: /settings
    Disallow: /uploads
    Disallow: /integrations
    Disallow: /users/

    Sitemap: #{Seo.page_url("/sitemap.xml")}
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  def sitemap(conn, _params) do
    urls = ["/", "/privacy", "/terms"]

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.map_join(urls, "\n", &sitemap_entry/1)}
    </urlset>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, body)
  end

  defp sitemap_entry(path) do
    "  <url><loc>#{Seo.page_url(path)}</loc></url>"
  end
end
