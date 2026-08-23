defmodule Konevo.ReleaseTest do
  use Konevo.DataCase

  import Konevo.AccountsFixtures

  alias Konevo.Accounts
  alias Konevo.Release

  test "create_owner/0 creates one owner and is idempotent" do
    email = unique_user_email()
    password = valid_user_password()

    previous_email = System.get_env("KONEVO_OWNER_EMAIL")
    previous_password = System.get_env("KONEVO_OWNER_PASSWORD")

    System.put_env("KONEVO_OWNER_EMAIL", email)
    System.put_env("KONEVO_OWNER_PASSWORD", password)

    on_exit(fn ->
      restore_env("KONEVO_OWNER_EMAIL", previous_email)
      restore_env("KONEVO_OWNER_PASSWORD", previous_password)
    end)

    assert {:ok, %{membership: membership}} = Release.create_owner()
    assert membership.role == :owner
    assert Accounts.get_user_by_email_and_password(email, password)
    assert {:ok, :already_exists} = Release.create_owner()
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
