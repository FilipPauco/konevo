defmodule Konevo.Automation.Policy do
  @moduledoc false

  @behaviour Bodyguard.Policy

  alias Konevo.Accounts.User
  alias Konevo.Permissions

  def authorize(action, %User{} = user, %{org: org})
      when action in [:read, :create, :update, :delete] do
    to_auth(Permissions.can?(user, org, :automation, action))
  end

  def authorize(_action, _user, _params), do: {:error, :unauthorized}

  defp to_auth(true), do: :ok
  defp to_auth(false), do: {:error, :unauthorized}
end
