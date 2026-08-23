defmodule KonevoWeb.Plugs.LoadPermissions do
  @moduledoc """
  Enriches `current_scope` with the current org and membership.

  Must run after `RequireMembership` (which assigns `current_org` and `current_membership`).

  Updates `conn.assigns.current_scope` from a user-only scope to a full
  org-scoped scope using `Scope.for_user_in_org/3`.
  """

  import Plug.Conn
  alias Konevo.Accounts.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    scope = conn.assigns[:current_scope]
    org = conn.assigns[:current_org]
    membership = conn.assigns[:current_membership]

    if scope && scope.user && org && membership do
      assign(conn, :current_scope, Scope.for_user_in_org(scope.user, org, membership))
    else
      conn
    end
  end
end
