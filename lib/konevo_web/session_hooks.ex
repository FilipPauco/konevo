defmodule KonevoWeb.SessionHooks do
  @moduledoc """
  LiveView `on_mount` hooks for session management.

  ## Hooks

    - `:subscribe_session` — subscribes to PubSub for the current user so that
      any server-side session revocation (logout, password change, role change)
      instantly disconnects open tabs.

    - `:verify_token_on_event` — attaches a hook that verifies the session token
      before every `handle_event`, catching quietly-expired tokens even when no
      server-side event triggers a revocation broadcast.

  ## Usage (in router)

      live_session :require_authenticated_user,
        on_mount: [
          {KonevoWeb.UserAuth, :require_authenticated},
          {KonevoWeb.SessionHooks, :subscribe_session},
          {KonevoWeb.SessionHooks, :verify_token_on_event}
        ] do
        ...
      end
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]
  alias Konevo.Accounts
  alias Konevo.Accounts.Scope
  alias KonevoWeb.Plugs.LoadOrganization

  @doc """
  Loads the organization from the socket's host URI (subdomain) and enriches
  `current_scope` with the org and membership.

  Must run after `{KonevoWeb.UserAuth, :require_authenticated}`.

  Halts with a redirect to the login page if:
    - the host has no subdomain (no-op — continues without org context)
    - the user has no membership in the org from the subdomain (forbidden)
  """
  def on_mount(:load_org_scope, _params, _session, socket) do
    scope = socket.assigns[:current_scope]
    host = socket.host_uri && socket.host_uri.host

    case {scope, LoadOrganization.extract_slug(host)} do
      {nil, _} ->
        {:cont, socket}

      {_, nil} ->
        {:cont, maybe_assign_public_org(socket, scope)}

      {%Scope{user: user}, slug} when not is_nil(user) ->
        org = Accounts.get_organization_by_slug(slug)

        cond do
          is_nil(org) ->
            raise Ecto.NoResultsError, queryable: Konevo.Accounts.Organization

          not Accounts.organization_active?(org) ->
            raise Ecto.NoResultsError, queryable: Konevo.Accounts.Organization

          is_nil(Konevo.Permissions.get_membership(user, org)) ->
            raise Ecto.NoResultsError, queryable: Konevo.Accounts.Organization

          true ->
            membership = Konevo.Permissions.get_membership(user, org)
            enriched_scope = Scope.for_user_in_org(user, org, membership)
            {:cont, assign(socket, :current_scope, enriched_scope)}
        end
    end
  end

  def on_mount(:subscribe_session, _params, _session, socket) do
    if connected?(socket) do
      user = socket.assigns.current_scope && socket.assigns.current_scope.user

      if user do
        Phoenix.PubSub.subscribe(Konevo.PubSub, "user_sessions:#{user.id}")
      end
    end

    {:cont, socket}
  end

  def on_mount(:verify_token_on_event, _params, session, socket) do
    socket =
      socket
      |> assign(:_user_token, session["user_token"])
      |> attach_hook(:verify_session, :handle_event, &verify_session/3)

    {:cont, socket}
  end

  # Runs before every handle_event clause in any LiveView using this hook.
  defp verify_session(_event, _params, socket) do
    token = socket.assigns[:_user_token]
    org = socket.assigns.current_scope && socket.assigns.current_scope.org

    case {token && Accounts.get_user_by_session_token(token), org} do
      {nil, _org} ->
        socket =
          socket
          |> put_flash(:error, "Your session has expired. Please log in again")
          |> redirect(to: "/users/log-in")

        {:halt, socket}

      {_user, nil} ->
        {:cont, socket}

      {_user, organization} ->
        if Accounts.organization_active?(organization) do
          {:cont, socket}
        else
          {:halt, redirect(socket, to: "/")}
        end
    end
  end

  defp maybe_assign_public_org(socket, scope) do
    default_slug = Application.get_env(:konevo, :default_tenant_slug, "public")
    org = Accounts.get_organization_by_slug(default_slug)

    with %_{} <- org,
         true <- Accounts.organization_active?(org),
         %Scope{user: user} <- scope,
         true <- not is_nil(user),
         membership when not is_nil(membership) <-
           Konevo.Permissions.get_membership(user, org) do
      enriched_scope = Scope.for_user_in_org(user, org, membership)
      assign(socket, :current_scope, enriched_scope)
    else
      _ -> socket
    end
  end
end
