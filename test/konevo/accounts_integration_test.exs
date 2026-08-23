defmodule Konevo.AccountsIntegrationTest do
  use Konevo.DataCase, async: true

  @moduletag :integration

  import Konevo.AccountsFixtures

  alias Konevo.Accounts

  describe "user registration and login flow" do
    test "registers a user and logs them in via magic link" do
      email = unique_user_email()

      assert {:ok, user} = Accounts.register_user(%{email: email})
      assert user.email == email
      refute user.confirmed_at

      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      assert {:ok, {logged_in_user, _expired_tokens}} =
               Accounts.login_user_by_magic_link(token)

      assert logged_in_user.id == user.id
      assert logged_in_user.confirmed_at
    end

    test "get_user_by_email/1 returns the user after registration" do
      user = unconfirmed_user_fixture()
      assert fetched = Accounts.get_user_by_email(user.email)
      assert fetched.id == user.id
    end
  end
end
