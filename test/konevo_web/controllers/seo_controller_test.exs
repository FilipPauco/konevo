defmodule KonevoWeb.SeoControllerTest do
  use KonevoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

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

  test "public product pages render parseable JSON-LD", %{conn: conn} do
    for path <- ["/", "/demo"] do
      scripts =
        conn
        |> get(path)
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query("script[type='application/ld+json']")

      assert Enum.count(scripts) == 1
      assert {:ok, data} = scripts |> LazyHTML.text() |> Jason.decode()
      assert data["@context"] == "https://schema.org"
      assert data["@type"] == "SoftwareApplication"
      assert data["name"] == "Konevo"
      assert data["url"] == Seo.page_url("/")
    end
  end

  test "JSON-LD cannot inject markup or consume the rest of the document" do
    for payload <- [
          "</script><script id='injected-script'>alert(1)</script>",
          "</ScRiPt><img id='injected-image' src=x onerror=alert(1)>",
          "<!--<script>",
          "Quotes: \" & < > / \\ and separators: \u2028\u2029"
        ] do
      data = Map.put(Seo.software_application_json_ld(), "description", payload)

      document =
        render_component(&KonevoWeb.Layouts.root/1,
          seo_json_ld: data,
          inner_content: "JSON-LD boundary check"
        )
        |> LazyHTML.from_document()

      scripts = LazyHTML.query(document, "script[type='application/ld+json']")
      assert Enum.count(scripts) == 1
      assert {:ok, ^data} = scripts |> LazyHTML.text() |> Jason.decode()
      assert Enum.empty?(LazyHTML.query(document, "#injected-script, #injected-image"))
      assert document |> LazyHTML.query("body") |> LazyHTML.text() =~ "JSON-LD boundary check"
    end
  end
end
