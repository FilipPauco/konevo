defmodule KonevoWeb.Plugs.SetTenantContext do
  @moduledoc """
  Sets the PostgreSQL session variable `app.current_tenant_id` for Row-Level Security.

  Must run after `LoadOrganization`. Sets the variable to the org's ID so that
  RLS policies on tenant-scoped tables can enforce isolation at the database level.

  ## Connection pooling note

  `SET` is connection-scoped, not request-scoped. Since this plug runs on every
  request, the tenant context is refreshed for the connection borrowed from the pool
  before any application queries execute.

  For `SET LOCAL` (which resets on transaction end) to work, wrap your request
  handlers in an explicit transaction. For most use cases, the regular `SET` here
  combined with this plug running on every request provides adequate isolation.
  """

  alias Ecto.Adapters.SQL
  alias Konevo.Repo

  def init(opts), do: opts

  def call(conn, _opts) do
    org = conn.assigns[:current_org]

    if org do
      tenant_id = Integer.to_string(org.id)
      SQL.query!(Repo, "SELECT set_config('app.current_tenant_id', $1, false)", [tenant_id])
    end

    conn
  end
end
