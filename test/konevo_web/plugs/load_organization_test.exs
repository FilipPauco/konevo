defmodule KonevoWeb.Plugs.LoadOrganizationTest do
  use KonevoWeb.ConnCase, async: true

  import Konevo.Factory

  alias KonevoWeb.Plugs.LoadOrganization

  defp call(conn), do: LoadOrganization.call(conn, [])

  # Simulate a request on the given host by updating conn.host.
  defp with_host(conn, host), do: %{conn | host: host}

  # ---------------------------------------------------------------------------
  # extract_slug/1 — pure unit, no DB
  # ---------------------------------------------------------------------------

  describe "extract_slug/1" do
    test "returns nil for base host (no subdomain)" do
      base = KonevoWeb.Endpoint.config(:url)[:host]
      assert LoadOrganization.extract_slug(base) == nil
    end

    test "returns nil for www prefix" do
      base = KonevoWeb.Endpoint.config(:url)[:host]
      assert LoadOrganization.extract_slug("www.#{base}") == nil
    end

    test "returns nil for bare localhost" do
      assert LoadOrganization.extract_slug("localhost") == nil
    end

    test "returns slug for subdomain" do
      assert LoadOrganization.extract_slug("myorg.localhost") == "myorg"
    end

    test "returns slug for multi-part base host" do
      assert LoadOrganization.extract_slug("acme.konevo.app") == "acme"
    end

    test "returns nil for IP-like first segment" do
      assert LoadOrganization.extract_slug("192.168.1.1") == nil
    end
  end

  # ---------------------------------------------------------------------------
  # call/2 — bare domain → public org
  # ---------------------------------------------------------------------------

  describe "bare domain (no subdomain)" do
    test "assigns public org when slug 'public' org exists", %{conn: conn} do
      org = insert(:organization, slug: "public")

      result = conn |> with_host("localhost") |> call()

      assert result.assigns.current_org.id == org.id
    end

    test "assigns nil when no org with slug 'public' exists", %{conn: conn} do
      # No public org seeded — ensure it does not exist
      result = conn |> with_host("localhost") |> call()

      assert result.assigns.current_org == nil
    end
  end

  # ---------------------------------------------------------------------------
  # call/2 — subdomain → matching org
  # ---------------------------------------------------------------------------

  describe "subdomain" do
    test "assigns org matching the subdomain slug", %{conn: conn} do
      org = insert(:organization, slug: "acme")

      result = conn |> with_host("acme.localhost") |> call()

      assert result.assigns.current_org.id == org.id
    end

    test "assigns nil when no org matches the subdomain slug", %{conn: conn} do
      result = conn |> with_host("nonexistent.localhost") |> call()

      assert result.assigns.current_org == nil
    end

    test "does not assign a different org for the wrong subdomain", %{conn: conn} do
      _acme = insert(:organization, slug: "acme")
      _beta = insert(:organization, slug: "beta")

      result = conn |> with_host("acme.localhost") |> call()

      assert result.assigns.current_org.slug == "acme"
    end

    test "slug lookup is case-insensitive (host is lowercased)", %{conn: conn} do
      org = insert(:organization, slug: "acme")

      result = conn |> with_host("ACME.localhost") |> call()

      assert result.assigns.current_org.id == org.id
    end
  end
end
