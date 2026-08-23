defmodule Konevo.Deals.Policy do
  @moduledoc false

  @behaviour Bodyguard.Policy

  alias Konevo.Accounts.User
  alias Konevo.Deals.Deal
  alias Konevo.Permissions

  def authorize(action, %User{} = user, %{org: org})
      when action in [:create, :read, :update, :delete] do
    to_auth(Permissions.can?(user, org, :deals, action))
  end

  def authorize(:update, %User{} = user, %{org: org, deal: %Deal{}}) do
    to_auth(Permissions.can?(user, org, :deals, :update))
  end

  def authorize(:delete, %User{} = user, %{org: org, deal: %Deal{}}) do
    to_auth(Permissions.can?(user, org, :deals, :delete))
  end

  def authorize(_action, _user, _params), do: {:error, :unauthorized}

  defp to_auth(true), do: :ok
  defp to_auth(false), do: {:error, :unauthorized}
end
