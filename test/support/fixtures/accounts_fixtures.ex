defmodule Konevo.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Konevo.Accounts` context.
  """

  import Ecto.Query
  import Konevo.Factory

  alias Konevo.Accounts
  alias Konevo.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "Hello world!1"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  # Creates a confirmed user directly via ExMachina — bypasses the magic-link
  # flow for speed. Use `unconfirmed_user_fixture` when testing the auth flow.
  def user_fixture(attrs \\ %{}) do
    insert(:user, attrs)
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Konevo.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Konevo.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Konevo.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end

  # --- Organization / Membership fixtures ---

  def unique_org_slug, do: "org-#{System.unique_integer([:positive])}"

  def org_fixture(attrs \\ %{}) do
    insert(:organization, attrs)
  end

  @doc """
  Creates a user + org + owner membership in one call.
  Returns `%{user: user, org: org, membership: membership, scope: scope}`.
  """
  def user_with_org_fixture(role \\ :owner) do
    user = insert(:user)
    org = insert(:organization)
    {:ok, membership} = Accounts.create_membership(user, org, role)
    scope = Scope.for_user_in_org(user, org, membership)
    %{user: user, org: org, membership: membership, scope: scope}
  end

  @doc """
  Adds an existing user to an existing org with the given role.
  Returns the membership and an enriched scope.
  """
  def add_member_fixture(user, org, role \\ :member) do
    {:ok, membership} = Accounts.create_membership(user, org, role)
    scope = Scope.for_user_in_org(user, org, membership)
    %{membership: membership, scope: scope}
  end
end
