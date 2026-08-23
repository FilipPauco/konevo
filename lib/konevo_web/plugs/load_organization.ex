defmodule KonevoWeb.Plugs.LoadOrganization do
  @moduledoc """
  Loads the current organization from the request subdomain.

  Parses the first segment of the host as the org slug.
  E.g., `acme.konevo.com` → looks up org with slug "acme".

  Assigns:
    - `conn.assigns.current_org` – the organization struct, or nil if not found/applicable.

  Does nothing (assigns nil) for:
    - `localhost` or IP addresses
    - hosts with no subdomain
  """

  import Plug.Conn
  alias Konevo.Accounts

  def init(opts), do: opts

  @doc """
  The reserved slug for the default public tenant accessible on the bare domain.
  """
  @default_tenant_slug Application.compile_env(:konevo, :default_tenant_slug, "public")

  def call(conn, _opts) do
    case extract_slug(conn.host) do
      nil ->
        # Bare domain (no subdomain) → load the reserved public tenant.
        org = Accounts.get_organization_by_slug(@default_tenant_slug)
        assign(conn, :current_org, org)

      slug ->
        org = Accounts.get_organization_by_slug(slug)
        assign(conn, :current_org, org)
    end
  end

  # Returns nil for bare hosts like "localhost" or IPs; returns subdomain slug otherwise.
  @doc "Returns the workspace slug encoded in a subdomain host."
  def extract_slug(host) when is_binary(host) do
    host = String.downcase(host)
    parts = String.split(host, ".")
    base_host = KonevoWeb.Endpoint.config(:url)[:host]

    cond do
      host == base_host -> nil
      host == "www.#{base_host}" -> nil
      length(parts) < 2 -> nil
      # IP address or plain "localhost"
      Regex.match?(~r/^\d+$/, hd(parts)) -> nil
      hd(parts) == "www" -> nil
      true -> hd(parts)
    end
  end

  def extract_slug(_host), do: nil
end
