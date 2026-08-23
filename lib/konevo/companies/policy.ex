defmodule Konevo.Companies.Policy do
  @moduledoc false

  @behaviour Bodyguard.Policy

  alias Konevo.Accounts.User
  alias Konevo.Companies.Company
  alias Konevo.Permissions

  def authorize(action, %User{} = user, %{org: org}) when action in [:create, :read] do
    to_auth(Permissions.can?(user, org, :companies, action))
  end

  def authorize(action, %User{} = user, %{
        org: %{id: organization_id} = org,
        company: %Company{organization_id: organization_id}
      })
      when action in [:update, :delete] do
    to_auth(Permissions.can?(user, org, :companies, action))
  end

  def authorize(_action, _user, _params), do: {:error, :unauthorized}

  defp to_auth(true), do: :ok
  defp to_auth(false), do: {:error, :unauthorized}
end
