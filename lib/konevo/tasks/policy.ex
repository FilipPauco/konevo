defmodule Konevo.Tasks.Policy do
  @moduledoc false

  @behaviour Bodyguard.Policy

  alias Konevo.Accounts.User
  alias Konevo.Permissions
  alias Konevo.Tasks.Task

  def authorize(action, %User{} = user, %{org: org}) when action in [:create, :read] do
    to_auth(Permissions.can?(user, org, :tasks, action))
  end

  def authorize(:update, %User{} = user, %{org: org, task: %Task{}}) do
    to_auth(Permissions.can?(user, org, :tasks, :update))
  end

  def authorize(:delete, %User{} = user, %{org: org, task: %Task{}}) do
    to_auth(Permissions.can?(user, org, :tasks, :delete))
  end

  def authorize(_action, _user, _params), do: {:error, :unauthorized}

  defp to_auth(true), do: :ok
  defp to_auth(false), do: {:error, :unauthorized}
end
