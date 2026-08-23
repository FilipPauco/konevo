defmodule KonevoWeb.Plugs.RequireMembership do
  @moduledoc """
  Halts the request with 404 if the current user has no membership in `current_org`.

  Must run after `LoadOrganization` and `fetch_current_scope_for_user`.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Konevo.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    org = conn.assigns[:current_org]
    scope = conn.assigns[:current_scope]

    cond do
      is_nil(org) or not Accounts.organization_active?(org) ->
        conn
        |> put_status(:not_found)
        |> put_view(KonevoWeb.ErrorHTML)
        |> render(:"404")
        |> halt()

      is_nil(scope) or is_nil(scope.user) ->
        conn
        |> put_status(:unauthorized)
        |> put_view(KonevoWeb.ErrorHTML)
        |> render(:"401")
        |> halt()

      true ->
        membership = Konevo.Permissions.get_membership(scope.user, org)

        if membership do
          assign(conn, :current_membership, membership)
        else
          conn
          |> put_status(:not_found)
          |> put_view(KonevoWeb.ErrorHTML)
          |> render(:"404")
          |> halt()
        end
    end
  end
end
