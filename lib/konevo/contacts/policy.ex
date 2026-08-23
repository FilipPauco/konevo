defmodule Konevo.Contacts.Policy do
  @moduledoc false

  @behaviour Bodyguard.Policy

  alias Konevo.Accounts.User
  alias Konevo.Contacts.Contact
  alias Konevo.Permissions

  def authorize(action, %User{} = user, %{org: org}) when action in [:create, :read, :update] do
    to_auth(Permissions.can?(user, org, :contacts, action))
  end

  def authorize(:delete, %User{} = user, %{org: org, contact: %Contact{}}) do
    to_auth(Permissions.can?(user, org, :contacts, :delete))
  end

  def authorize(:delete, %User{} = user, %{org: org}) do
    to_auth(Permissions.can?(user, org, :contacts, :delete))
  end

  def authorize(_action, _user, _params), do: {:error, :unauthorized}

  defp to_auth(true), do: :ok
  defp to_auth(false), do: {:error, :unauthorized}
end
