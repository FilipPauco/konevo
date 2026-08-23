defmodule KonevoWeb.Plugs.RequireTenantAccessIfAuthenticated do
  @moduledoc """
  Allows public visitors through while hiding tenant pages from authenticated
  users who are not members of the organization selected by the host.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Konevo.{Accounts, Permissions}
  alias KonevoWeb.Plugs.LoadOrganization

  def init(opts), do: opts

  def call(%{assigns: %{current_scope: %{user: user}, current_org: org}} = conn, _opts)
      when not is_nil(user) and not is_nil(org) do
    if Accounts.organization_active?(org) and Permissions.get_membership(user, org),
      do: conn,
      else: not_found(conn)
  end

  def call(%{assigns: %{current_scope: %{user: user}}} = conn, _opts) when not is_nil(user) do
    if LoadOrganization.extract_slug(conn.host), do: not_found(conn), else: conn
  end

  def call(conn, _opts), do: conn

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(KonevoWeb.ErrorHTML)
    |> render(:"404")
    |> halt()
  end
end
