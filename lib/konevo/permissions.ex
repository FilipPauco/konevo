defmodule Konevo.Permissions do
  @moduledoc """
  Central permission matrix for role-based access control.

  Role hierarchy (higher number = more permissions):
    owner > admin > member > viewer
  """

  import Ecto.Query, warn: false

  alias Konevo.Accounts.{Membership, Organization, User}
  alias Konevo.Repo

  @role_hierarchy %{owner: 4, admin: 3, member: 2, viewer: 1}

  @doc """
  Returns true if the user can perform `action` on `resource` within `org`.

  Checks role-based rules and custom per-membership permissions.
  """
  def can?(%User{} = user, %Organization{} = org, resource, action) do
    case get_membership(user, org) do
      nil ->
        false

      membership ->
        can?(membership, resource, action)
    end
  end

  @doc """
  Returns true if a loaded membership can perform `action` on `resource`.
  """
  def can?(%Membership{} = membership, resource, action) do
    role_allows?(membership.role, resource, action) or
      custom_allows?(membership, resource, action)
  end

  @doc """
  Returns true if the user has at least the `required_role` in `org`.
  """
  def has_role?(%User{} = user, %Organization{} = org, required_role) do
    case get_membership(user, org) do
      nil ->
        false

      %{role: role} ->
        Map.get(@role_hierarchy, role, 0) >= Map.get(@role_hierarchy, required_role, 999)
    end
  end

  @doc """
  Returns the membership for the user in the org, or nil.
  """
  def get_membership(%User{id: user_id}, %Organization{id: org_id}) do
    Membership
    |> where(
      [m],
      m.user_id == ^user_id and m.organization_id == ^org_id and is_nil(m.archived_at)
    )
    |> Repo.one()
  end

  # owner can do everything
  defp role_allows?(:owner, _resource, _action), do: true

  # admin: almost everything except deleting reports
  defp role_allows?(:admin, :reports, :delete), do: false
  defp role_allows?(:admin, _resource, _action), do: true

  # member: CRUD on core CRM resources only
  defp role_allows?(:member, resource, action)
       when action in [:read, :create, :update] and
              resource in [:contacts, :companies, :deals, :tasks, :inbox, :messaging],
       do: true

  defp role_allows?(:member, :tasks, :delete), do: true

  defp role_allows?(:member, :compliance, :read), do: true

  defp role_allows?(:member, :automation, action)
       when action in [:read, :create, :update],
       do: true

  # viewer: read-only everywhere
  defp role_allows?(:viewer, _resource, :read), do: true

  defp role_allows?(_role, _resource, _action), do: false

  defp custom_allows?(%Membership{custom_permissions: perms}, resource, action) do
    "#{resource}:#{action}" in perms
  end
end
