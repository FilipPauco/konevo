defmodule KonevoWeb.SeoControllerTest do
  use KonevoWeb.ConnCase, async: true

  alias KonevoWeb.Seo

  test "serves crawl rules with a sitemap location", %{conn: conn} do
    conn = get(conn, "/robots.txt")

    assert response(conn, 200) =~ "User-agent: *"
    assert response(conn, 200) =~ "Disallow: /dashboard"
    assert response(conn, 200) =~ "Sitemap: #{Seo.page_url("/sitemap.xml")}"
    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "text/plain"
  end

  test "serves a sitemap for public pages only", %{conn: conn} do
    conn = get(conn, "/sitemap.xml")
    body = response(conn, 200)

    assert body =~ "<urlset"
    assert body =~ "<loc>#{Seo.page_url("/")}</loc>"
    assert body =~ "<loc>#{Seo.page_url("/privacy")}</loc>"
    assert body =~ "<loc>#{Seo.page_url("/terms")}</loc>"
    refute body =~ "/dashboard"
    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "application/xml"
  end

  test "public pages include indexable share metadata", %{conn: conn} do
    html = conn |> get("/") |> html_response(200)

    assert html =~ ~s(name="description")
    assert html =~ ~s(name="robots" content="index, follow")
    assert html =~ ~s(rel="canonical")
    assert html =~ ~s(property="og:image")
    assert html =~ ~s(name="twitter:card" content="summary_large_image")
    assert html =~ "application/ld+json"
  end

  test "account pages are not indexed", %{conn: conn} do
    html = conn |> get("/users/log-in") |> html_response(200)

    assert html =~ ~s(name="robots" content="noindex, nofollow")
    refute html =~ ~s(rel="canonical")
  end
end
