defmodule Konevo.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false

  alias Konevo.Deals.DefaultStages
  alias Konevo.Repo

  alias Konevo.Accounts.{
    Membership,
    Organization,
    Scope,
    TenantInvitation,
    User,
    UserNotifier,
    UserToken
  }

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Lists users with the given IDs who belong to the scoped organization.
  """
  def list_organization_users_by_ids(%Scope{org: %Organization{id: org_id}}, ids)
      when is_list(ids) do
    Repo.all(
      from u in User,
        join: m in Membership,
        on: m.user_id == u.id,
        where: m.organization_id == ^org_id and is_nil(m.archived_at) and u.id in ^ids
    )
  end

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Finds or registers a user and creates a new organization in a single transaction.

  Existing users are reused because user identities are global. The user is
  made the `:owner` of the new organization.

  Returns `{:ok, %{user: user, org: org, membership: membership}}` or
  `{:error, failed_op, changeset, changes}`.

  ## Examples

      iex> register_user_with_org(%{email: "alice@example.com", org_name: "Acme", org_slug: "acme"})
      {:ok, %{user: %User{}, org: %Organization{}, membership: %Membership{}}}

  """
  def register_user_with_org(%{"email" => _} = attrs) do
    user_attrs = Map.take(attrs, ["email"])
    org_name = Map.get(attrs, "org_name", "")
    org_slug = Map.get(attrs, "org_slug", "")

    Ecto.Multi.new()
    |> Ecto.Multi.run(:user, fn repo, _changes -> find_or_insert_user(repo, user_attrs) end)
    |> Ecto.Multi.insert(:org, fn _changes ->
      Organization.changeset(%Organization{}, %{name: org_name, slug: org_slug})
    end)
    |> Ecto.Multi.run(:deal_stages, fn _repo, %{org: org} -> DefaultStages.ensure(org) end)
    |> Ecto.Multi.insert(:membership, fn %{user: user, org: org} ->
      Membership.changeset(%Membership{user_id: user.id, organization_id: org.id}, %{role: :owner})
    end)
    |> Repo.transaction()
  end

  @doc """
  Finds or registers a user and adds them to the default public organization.

  Returns `{:ok, %{user: user, org: org, membership: membership}}` or
  `{:error, failed_op, reason, changes}`.
  """
  def register_user_with_default_org(%{"email" => _} = attrs) do
    user_attrs = Map.take(attrs, ["email"])
    default_slug = Application.get_env(:konevo, :default_tenant_slug, "public")

    Ecto.Multi.new()
    |> Ecto.Multi.run(:user, fn repo, _changes -> find_or_insert_user(repo, user_attrs) end)
    |> Ecto.Multi.run(:org, fn repo, _changes -> get_or_create_default_org(repo, default_slug) end)
    |> Ecto.Multi.run(:deal_stages, fn _repo, %{org: org} -> DefaultStages.ensure(org) end)
    |> Ecto.Multi.run(:membership, fn repo, %{user: user, org: org} ->
      find_or_insert_membership(repo, user, org, :member)
    end)
    |> Repo.transaction()
  end

  @doc """
  Registers a new password user and creates an organization in a single transaction.

  Unlike `register_user_with_org/1`, this function never reuses an existing
  email address. This prevents a password registration from attaching an
  existing user to a new organization.
  """
  def register_password_user_with_org(%{"email" => _, "password" => _} = attrs) do
    user_attrs = Map.take(attrs, ["email", "password", "password_confirmation"])
    org_name = Map.get(attrs, "org_name", "")
    org_slug = Map.get(attrs, "org_slug", "")

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, registration_changeset(user_attrs))
    |> Ecto.Multi.insert(:org, fn _changes ->
      Organization.changeset(%Organization{}, %{name: org_name, slug: org_slug})
    end)
    |> Ecto.Multi.run(:deal_stages, fn _repo, %{org: org} -> DefaultStages.ensure(org) end)
    |> Ecto.Multi.insert(:membership, fn %{user: user, org: org} ->
      Membership.changeset(%Membership{user_id: user.id, organization_id: org.id}, %{role: :owner})
    end)
    |> Repo.transaction()
  end

  @doc """
  Registers a new password user and adds them to the default public organization.

  Existing email addresses are rejected rather than reused.
  """
  def register_password_user_with_default_org(%{"email" => _, "password" => _} = attrs) do
    user_attrs = Map.take(attrs, ["email", "password", "password_confirmation"])
    default_slug = Application.get_env(:konevo, :default_tenant_slug, "public")

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, registration_changeset(user_attrs))
    |> Ecto.Multi.run(:org, fn repo, _changes -> get_or_create_default_org(repo, default_slug) end)
    |> Ecto.Multi.run(:deal_stages, fn _repo, %{org: org} -> DefaultStages.ensure(org) end)
    |> Ecto.Multi.insert(:membership, fn %{user: user, org: org} ->
      Membership.changeset(%Membership{user_id: user.id, organization_id: org.id}, %{
        role: :member
      })
    end)
    |> Repo.transaction()
  end

  @doc """
  Registers the initial password-protected owner in the default workspace.

  This is intended for private deployments where public registration is
  disabled. Existing email addresses are rejected rather than reused.
  """
  def register_password_owner_with_default_org(%{"email" => _, "password" => _} = attrs) do
    user_attrs = Map.take(attrs, ["email", "password", "password_confirmation"])
    default_slug = Application.get_env(:konevo, :default_tenant_slug, "public")

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, registration_changeset(user_attrs))
    |> Ecto.Multi.run(:org, fn repo, _changes -> get_or_create_default_org(repo, default_slug) end)
    |> Ecto.Multi.run(:deal_stages, fn _repo, %{org: org} -> DefaultStages.ensure(org) end)
    |> Ecto.Multi.insert(:membership, fn %{user: user, org: org} ->
      Membership.changeset(%Membership{user_id: user.id, organization_id: org.id}, %{
        role: :owner
      })
    end)
    |> Repo.transaction()
  end

  defp get_or_create_default_org(repo, slug) do
    case repo.get_by(Organization, slug: slug) do
      nil -> create_default_org(repo, slug)
      org -> {:ok, org}
    end
  end

  defp create_default_org(repo, slug) do
    %Organization{}
    |> Organization.changeset(%{name: "Public", slug: slug})
    |> repo.insert()
  end

  defp find_or_insert_user(repo, %{"email" => email} = attrs) do
    case repo.get_by(User, email: email) do
      nil -> repo.insert(User.email_changeset(%User{}, attrs))
      user -> {:ok, user}
    end
  end

  defp registration_changeset(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> User.password_changeset(attrs)
  end

  defp find_or_insert_membership(repo, %User{} = user, %Organization{} = org, role) do
    case repo.get_by(Membership, user_id: user.id, organization_id: org.id) do
      nil ->
        %Membership{user_id: user.id, organization_id: org.id}
        |> Membership.changeset(%{role: role})
        |> repo.insert()

      membership ->
        {:ok, membership}
    end
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Konevo.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Konevo.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    result =
      user
      |> User.password_changeset(attrs)
      |> update_user_and_delete_all_tokens()

    with {:ok, {updated_user, _tokens}} <- result do
      Phoenix.PubSub.broadcast(
        Konevo.PubSub,
        "user_sessions:#{updated_user.id}",
        :session_revoked
      )

      result
    end
  end

  @doc """
  Gets the user associated with a valid password reset token.
  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_reset_password_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets a password with a valid reset token and expires all existing tokens.
  """
  def reset_user_password(token, attrs) do
    with {:ok, query} <- UserToken.verify_reset_password_token_query(token),
         {user, _token} <- Repo.one(query) do
      update_user_password(user, attrs)
    else
      _ -> {:error, :invalid_token}
    end
  end

  @doc """
  Updates the user's view preferences (contacts_view_mode, deals_view_mode).
  """
  def update_user_view_preferences(user, attrs) do
    user
    |> User.view_preferences_changeset(attrs)
    |> Repo.update()
  end

  ## Two-factor authentication

  @two_factor_secret_salt "two-factor-secret-v1"

  def two_factor_enabled?(%User{two_factor_secret: secret}) when is_binary(secret), do: true
  def two_factor_enabled?(_user), do: false

  def new_two_factor_secret, do: NimbleTOTP.secret()

  def two_factor_otpauth_uri(%User{} = user, secret) when is_binary(secret) do
    NimbleTOTP.otpauth_uri("Konevo:#{user.email}", secret, issuer: "Konevo")
  end

  def enable_two_factor(%User{} = user, secret, code)
      when is_binary(secret) and is_binary(code) do
    case valid_two_factor_code?(secret, code) do
      true ->
        now = DateTime.utc_now(:second)

        user
        |> User.two_factor_changeset(%{
          two_factor_secret: encrypt_two_factor_secret(secret),
          two_factor_last_used_at: now
        })
        |> Repo.update()

      false ->
        {:error, :invalid_code}
    end
  end

  def disable_two_factor(%User{} = user) do
    user
    |> User.two_factor_changeset(%{two_factor_secret: nil, two_factor_last_used_at: nil})
    |> Repo.update()
  end

  def verify_two_factor_code(%User{} = user, code) when is_binary(code) do
    with {:ok, secret} <- decrypt_two_factor_secret(user),
         true <- valid_two_factor_code?(secret, code, since: user.two_factor_last_used_at) do
      now = DateTime.utc_now(:second)

      case user |> User.two_factor_changeset(%{two_factor_last_used_at: now}) |> Repo.update() do
        {:ok, verified_user} -> {:ok, verified_user}
        {:error, _changeset} -> {:error, :verification_failed}
      end
    else
      _ -> {:error, :invalid_code}
    end
  end

  defp valid_two_factor_code?(secret, code, opts \\ []) do
    NimbleTOTP.valid?(secret, String.trim(code), opts)
  end

  defp encrypt_two_factor_secret(secret) do
    Phoenix.Token.encrypt(KonevoWeb.Endpoint, @two_factor_secret_salt, secret, max_age: :infinity)
  end

  defp decrypt_two_factor_secret(%User{two_factor_secret: encrypted}) when is_binary(encrypted) do
    Phoenix.Token.decrypt(KonevoWeb.Endpoint, @two_factor_secret_salt, encrypted,
      max_age: :infinity
    )
  end

  defp decrypt_two_factor_secret(_user), do: {:error, :two_factor_not_enabled}

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Delivers password reset instructions to the given user.
  """
  def deliver_reset_password_instructions(%User{} = user, reset_url_fun)
      when is_function(reset_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")

    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  ## Organizations

  def get_organization!(id), do: Repo.get!(Organization, id)

  def get_organization_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Organization, slug: slug)
  end

  def organization_active?(%Organization{id: id}) do
    Organization
    |> where([organization], organization.id == ^id and is_nil(organization.archived_at))
    |> Repo.exists?()
  end

  def organization_active?(_organization), do: false

  def create_organization(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:org, Organization.changeset(%Organization{}, attrs))
    |> Ecto.Multi.run(:deal_stages, fn _repo, %{org: org} -> DefaultStages.ensure(org) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{org: org}} -> {:ok, org}
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  def ensure_essential_data do
    default_slug = Application.get_env(:konevo, :default_tenant_slug, "public")

    Repo.transaction(fn ->
      {:ok, public_org} = get_or_create_default_org(Repo, default_slug)
      {:ok, _} = DefaultStages.ensure(public_org)

      Organization
      |> Repo.all()
      |> Enum.each(fn org ->
        {:ok, _} = DefaultStages.ensure(org)
      end)
    end)
  end

  ## Tenant invitations

  @tenant_invitation_validity_in_days 3

  def can_manage_tenants?(%Scope{user: %User{} = user, org: %Organization{} = org}) do
    org.slug == Application.fetch_env!(:konevo, :default_tenant_slug) and
      Konevo.Permissions.has_role?(user, org, :owner)
  end

  def can_manage_tenants?(_scope), do: false

  def list_tenant_invitations(opts \\ []) do
    search = opts |> Keyword.get(:search, "") |> String.trim()

    TenantInvitation
    |> join(:inner, [invitation], organization in assoc(invitation, :organization))
    |> search_tenant_invitations(search)
    |> preload([_invitation, organization], organization: organization)
    |> order_by([invitation], desc: invitation.inserted_at)
    |> Repo.all()
  end

  def archive_tenant(%Scope{} = scope, invitation_id) do
    update_tenant_archive_state(scope, invitation_id, DateTime.utc_now(:second))
  end

  def restore_tenant(%Scope{} = scope, invitation_id) do
    update_tenant_archive_state(scope, invitation_id, nil)
  end

  def create_tenant_invitation(%Scope{} = scope, attrs, invitation_url_fun)
      when is_function(invitation_url_fun, 2) do
    with true <- can_manage_tenants?(scope),
         {:ok, email} <- invitation_email(attrs) do
      case create_tenant_invitation_records(scope, attrs, email) do
        {:ok, %{organization: organization, invitation: invitation, token: token}} ->
          deliver_tenant_invitation(email, organization, invitation, token, invitation_url_fun)

        {:error, operation, reason, changes} ->
          {:error, operation, reason, changes}
      end
    else
      false -> {:error, :unauthorized}
      {:error, changeset} -> {:error, :invitation, changeset, %{}}
    end
  end

  defp create_tenant_invitation_records(scope, attrs, email) do
    raw_token = :crypto.strong_rand_bytes(32)
    token = Base.url_encode64(raw_token, padding: false)
    now = DateTime.utc_now(:second)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:organization, Organization.changeset(%Organization{}, attrs))
    |> Ecto.Multi.insert(:invitation, fn %{organization: organization} ->
      TenantInvitation.changeset(%TenantInvitation{}, %{
        email: email,
        token_hash: tenant_invitation_token_hash(raw_token),
        expires_at: DateTime.add(now, @tenant_invitation_validity_in_days, :day),
        organization_id: organization.id,
        invited_by_id: scope.user.id
      })
    end)
    |> Ecto.Multi.run(:token, fn _repo, _changes -> {:ok, token} end)
    |> Repo.transaction()
  end

  defp deliver_tenant_invitation(email, organization, invitation, token, invitation_url_fun) do
    invitation = Repo.preload(invitation, :organization)

    case UserNotifier.deliver_tenant_invitation(
           email,
           organization,
           invitation_url_fun.(organization, token)
         ) do
      {:ok, _email} -> {:ok, %{organization: organization, invitation: invitation}}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_tenant_invitation(token) when is_binary(token) do
    case decode_tenant_invitation_token(token) do
      {:ok, token_hash} ->
        TenantInvitation
        |> join(:inner, [invitation], organization in assoc(invitation, :organization))
        |> where(
          [invitation, organization],
          invitation.token_hash == ^token_hash and is_nil(organization.archived_at)
        )
        |> preload([_invitation, organization], organization: organization)
        |> Repo.one()
        |> active_tenant_invitation()

      _ ->
        nil
    end
  end

  def get_tenant_invitation(_token), do: nil

  def tenant_invitation_existing_user?(%TenantInvitation{email: email}) do
    match?(
      %User{hashed_password: hashed_password} when is_binary(hashed_password),
      get_user_by_email(email)
    )
  end

  def accept_tenant_invitation(token, params) when is_binary(token) and is_map(params) do
    Repo.transact(fn ->
      with {:ok, token_hash} <- decode_tenant_invitation_token(token),
           %TenantInvitation{} = invitation <- locked_active_tenant_invitation(token_hash),
           {:ok, user} <- invitation_user(invitation, params),
           {:ok, membership} <- create_membership(user, invitation.organization, :owner),
           {:ok, _} <- DefaultStages.ensure(invitation.organization),
           {:ok, invitation} <- accept_tenant_invitation_record(invitation) do
        {:ok, %{user: user, organization: invitation.organization, membership: membership}}
      else
        nil -> Repo.rollback(:invalid_or_expired)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def accept_tenant_invitation(_token, _params), do: {:error, :invalid_or_expired}

  defp invitation_email(attrs) do
    changeset = User.email_changeset(%User{}, attrs, validate_unique: false)

    if changeset.valid? do
      {:ok, Ecto.Changeset.get_field(changeset, :email)}
    else
      {:error, changeset}
    end
  end

  defp locked_active_tenant_invitation(token_hash) do
    TenantInvitation
    |> join(:inner, [invitation], organization in assoc(invitation, :organization))
    |> where(
      [invitation, organization],
      invitation.token_hash == ^token_hash and is_nil(invitation.accepted_at) and
        invitation.expires_at > ^DateTime.utc_now(:second) and is_nil(organization.archived_at)
    )
    |> preload([_invitation, organization], organization: organization)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp update_tenant_archive_state(scope, invitation_id, archived_at) do
    with true <- can_manage_tenants?(scope),
         {:ok, id} <- tenant_invitation_id(invitation_id),
         %TenantInvitation{} = invitation <- tenant_invitation_for_management(id),
         true <- tenant_archivable?(invitation.organization),
         {:ok, organization} <-
           invitation.organization
           |> Ecto.Changeset.change(archived_at: archived_at)
           |> Repo.update() do
      {:ok, %{invitation | organization: organization}}
    else
      false -> {:error, :unauthorized}
      :error -> {:error, :not_found}
      nil -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp tenant_invitation_for_management(id) do
    TenantInvitation
    |> where([invitation], invitation.id == ^id)
    |> preload(:organization)
    |> Repo.one()
  end

  defp tenant_archivable?(%Organization{slug: slug}) do
    slug != Application.fetch_env!(:konevo, :default_tenant_slug)
  end

  defp tenant_invitation_id(id) when is_integer(id), do: {:ok, id}

  defp tenant_invitation_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed_id, ""} -> {:ok, parsed_id}
      _ -> :error
    end
  end

  defp tenant_invitation_id(_id), do: :error

  defp active_tenant_invitation(
         %TenantInvitation{accepted_at: nil, expires_at: expires_at} = invitation
       ) do
    if DateTime.compare(expires_at, DateTime.utc_now(:second)) == :gt, do: invitation
  end

  defp active_tenant_invitation(_invitation), do: nil

  defp invitation_user(%TenantInvitation{email: email}, params) do
    case get_user_by_email(email) do
      nil ->
        %User{}
        |> User.email_changeset(%{"email" => email})
        |> User.password_changeset(params)
        |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
        |> Repo.insert()

      %User{hashed_password: hashed_password} = user when is_binary(hashed_password) ->
        if User.valid_password?(user, Map.get(params, "password", "")) do
          confirm_invited_user(user)
        else
          {:error, :invalid_password}
        end

      %User{} = user ->
        user
        |> User.password_changeset(params)
        |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
        |> Repo.update()
    end
  end

  defp confirm_invited_user(%User{confirmed_at: nil} = user),
    do: Repo.update(User.confirm_changeset(user))

  defp confirm_invited_user(%User{} = user), do: {:ok, user}

  defp accept_tenant_invitation_record(invitation) do
    invitation
    |> Ecto.Changeset.change(accepted_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  defp decode_tenant_invitation_token(token) do
    with {:ok, decoded_token} <- Base.url_decode64(token, padding: false) do
      {:ok, tenant_invitation_token_hash(decoded_token)}
    end
  end

  defp tenant_invitation_token_hash(token), do: :crypto.hash(:sha256, token)

  defp search_tenant_invitations(query, ""), do: query

  defp search_tenant_invitations(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [invitation, organization],
      ilike(organization.name, ^pattern) or ilike(organization.slug, ^pattern) or
        ilike(invitation.email, ^pattern)
    )
  end

  ## Memberships

  @doc """
  Returns all memberships for the org, preloaded with their user, ordered by role then email.
  """
  def list_members(%Organization{id: org_id}) do
    org_id
    |> members_query()
    |> filter_members_archive(:active)
    |> order_by([m, u], asc: m.role, asc: u.email)
    |> preload([_m, u], user: u)
    |> Repo.all()
  end

  @doc """
  Returns paginated memberships for the org with optional search and sort.
  """
  def list_members(%Organization{id: org_id}, opts) when is_list(opts) do
    search = Keyword.get(opts, :search, "")
    sort_by = Keyword.get(opts, :sort_by, :email)
    sort_dir = Keyword.get(opts, :sort_dir, :asc)
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 25)

    query =
      org_id
      |> members_query()
      |> filter_members_archive(Keyword.get(opts, :archive_filter, :active))
      |> search_members(search)

    total = Repo.aggregate(query, :count, :id)

    members =
      query
      |> sort_members(sort_by, sort_dir)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> preload([_m, u], user: u)
      |> Repo.all()

    {members, total}
  end

  @doc """
  Gets a membership by id within the given org.
  Raises `Ecto.NoResultsError` if not found.
  """
  def get_membership!(org, id) do
    Membership
    |> Repo.get_by!(id: id, organization_id: org.id)
    |> Repo.preload(:user)
  end

  @doc """
  Invites a user to the org with the given role.

  - If a user with that email already exists, they are added to the org directly.
  - If not, a new (unconfirmed) user is created and a magic link is sent.

  Returns `{:ok, membership}` or `{:error, reason}`.
  The caller must hold at least the `:admin` role.
  """
  def invite_member(%Organization{} = org, email, role, url_fun) when is_binary(email) do
    Repo.transact(fn ->
      user = find_or_register_user!(email)
      add_member_to_org(user, org, role, url_fun)
    end)
  catch
    {:error, reason} -> {:error, reason}
  end

  defp add_member_to_org(user, org, role, url_fun) do
    case Repo.get_by(Membership, user_id: user.id, organization_id: org.id) do
      nil ->
        with {:ok, m} <- create_membership(user, org, role) do
          deliver_login_instructions(user, url_fun)
          {:ok, Repo.preload(m, :user)}
        end

      _existing ->
        {:error, :already_member}
    end
  end

  defp find_or_register_user!(email) do
    case get_user_by_email(email) do
      nil ->
        case register_user(%{"email" => email}) do
          {:ok, u} -> u
          {:error, cs} -> throw({:error, cs})
        end

      existing ->
        existing
    end
  end

  def create_membership(%User{} = user, %Organization{} = org, role \\ :member) do
    %Membership{user_id: user.id, organization_id: org.id}
    |> Membership.changeset(%{role: role})
    |> Repo.insert()
  end

  def update_membership(%Membership{} = membership, attrs) do
    result =
      membership
      |> Membership.changeset(attrs)
      |> Repo.update()

    # Broadcast revocation so open tabs pick up role changes immediately.
    with {:ok, updated} <- result do
      user = Repo.get!(User, updated.user_id)
      revoke_all_sessions(user)
      {:ok, Repo.preload(updated, :user)}
    end
  end

  def delete_membership(%Membership{} = membership) do
    user = Repo.get!(User, membership.user_id)
    result = Repo.delete(membership)

    with {:ok, deleted} <- result do
      revoke_all_sessions(user)
      {:ok, deleted}
    end
  end

  def archive_membership(%User{} = actor, %Membership{} = membership, reason \\ nil) do
    if membership.role == :owner do
      {:error, :cannot_archive_owner}
    else
      user = Repo.get!(User, membership.user_id)

      result =
        membership
        |> Ecto.Changeset.change(%{
          archived_at: DateTime.utc_now(:second),
          archived_by_id: actor.id,
          archive_reason: reason
        })
        |> Repo.update()

      with {:ok, archived} <- result do
        revoke_all_sessions(user)
        {:ok, Repo.preload(archived, :user)}
      end
    end
  end

  def restore_membership(%Membership{} = membership) do
    membership
    |> Ecto.Changeset.change(%{archived_at: nil, archived_by_id: nil, archive_reason: nil})
    |> Repo.update()
    |> case do
      {:ok, restored} -> {:ok, Repo.preload(restored, :user)}
      error -> error
    end
  end

  ## Session revocation

  @doc """
  Revokes all active sessions for the given user and broadcasts `:session_revoked`
  over PubSub so any open LiveView tabs disconnect immediately.

  Call this on: logout, password change, role change, admin force-logout, account suspension.
  """
  def revoke_all_sessions(%User{} = user) do
    Repo.delete_all(from(t in UserToken, where: t.user_id == ^user.id and t.context == "session"))

    Phoenix.PubSub.broadcast(
      Konevo.PubSub,
      "user_sessions:#{user.id}",
      :session_revoked
    )

    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  defp members_query(org_id) do
    from m in Membership,
      where: m.organization_id == ^org_id,
      join: u in assoc(m, :user)
  end

  defp filter_members_archive(query, :archived),
    do: where(query, [m, _u], not is_nil(m.archived_at))

  defp filter_members_archive(query, :all), do: query

  defp filter_members_archive(query, _filter),
    do: where(query, [m, _u], is_nil(m.archived_at))

  defp search_members(query, search) when is_binary(search) do
    search = String.trim(search)

    if search == "" do
      query
    else
      pattern = "%#{search}%"

      where(
        query,
        [m, u],
        ilike(u.email, ^pattern) or fragment("? ILIKE ?", m.role, ^pattern)
      )
    end
  end

  defp sort_members(query, :role, :desc),
    do: order_by(query, [m, u], desc: m.role, asc: u.email)

  defp sort_members(query, :role, _dir),
    do: order_by(query, [m, u], asc: m.role, asc: u.email)

  defp sort_members(query, :inserted_at, :desc),
    do: order_by(query, [m, u], desc: m.inserted_at, asc: u.email)

  defp sort_members(query, :inserted_at, _dir),
    do: order_by(query, [m, u], asc: m.inserted_at, asc: u.email)

  defp sort_members(query, :email, :desc),
    do: order_by(query, [_m, u], desc: u.email)

  defp sort_members(query, _sort_by, _dir),
    do: order_by(query, [_m, u], asc: u.email)
end
