defmodule Konevo.AccountsTwoFactorTest do
  use Konevo.DataCase, async: true

  alias Ecto.Changeset
  alias Konevo.Accounts
  alias Konevo.Repo

  import Konevo.AccountsFixtures

  describe "two-factor authentication" do
    test "encrypts the secret and rejects a reused verification code" do
      user = user_fixture()
      secret = Accounts.new_two_factor_secret()
      code = NimbleTOTP.verification_code(secret)

      assert {:ok, enabled_user} = Accounts.enable_two_factor(user, secret, code)
      assert Accounts.two_factor_enabled?(enabled_user)
      refute enabled_user.two_factor_secret == secret

      enabled_user =
        enabled_user
        |> Changeset.change(
          two_factor_last_used_at:
            DateTime.utc_now() |> DateTime.add(-31, :second) |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      code = NimbleTOTP.verification_code(secret)
      assert {:ok, verified_user} = Accounts.verify_two_factor_code(enabled_user, code)
      assert verified_user.two_factor_last_used_at
      assert {:error, :invalid_code} = Accounts.verify_two_factor_code(verified_user, code)
    end

    test "does not enable two-factor authentication with an invalid code" do
      user = user_fixture()
      secret = Accounts.new_two_factor_secret()

      assert {:error, :invalid_code} = Accounts.enable_two_factor(user, secret, "000000")
      refute Accounts.two_factor_enabled?(Accounts.get_user!(user.id))
    end
  end
end
