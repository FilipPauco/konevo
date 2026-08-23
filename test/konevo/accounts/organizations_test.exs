defmodule Konevo.Accounts.OrganizationsTest do
  use Konevo.DataCase, async: true

  import Konevo.AccountsFixtures

  alias Konevo.Accounts
  alias Konevo.Accounts.{Membership, Organization, Scope, TenantInvitation}
  alias Konevo.Deals
  alias Konevo.Repo

  describe "create_organization/1" do
    test "creates with valid attrs" do
      slug = unique_org_slug()

      assert {:ok, %Organization{slug: ^slug}} =
               Accounts.create_organization(%{name: "Acme", slug: slug})
    end

    test "creates the default pipeline stages" do
      slug = unique_org_slug()

      assert {:ok, org} = Accounts.create_organization(%{name: "Acme", slug: slug})

      assert Enum.map(Deals.list_stages(%{org: org}), & &1.name) == [
               "Lead",
               "Qualified",
               "Proposal",
               "Negotiation",
               "Closed Won",
               "Closed Lost"
             ]
    end

    test "requires name and slug" do
      assert {:error, cs} = Accounts.create_organization(%{})
      assert %{name: [_], slug: [_]} = errors_on(cs)
    end

    test "enforces slug uniqueness" do
      slug = unique_org_slug()
      Accounts.create_organization(%{name: "First", slug: slug})
      assert {:error, cs} = Accounts.create_organization(%{name: "Second", slug: slug})
      assert %{slug: [_]} = errors_on(cs)
    end

    test "rejects invalid slug characters" do
      assert {:error, cs} = Accounts.create_organization(%{name: "Bad", slug: "Has Spaces!"})
      assert %{slug: [_]} = errors_on(cs)
    end
  end

  describe "ensure_essential_data/0" do
    test "backfills pipeline stages for existing organizations" do
      org = org_fixture()

      assert {:ok, :ok} = Accounts.ensure_essential_data()
      assert length(Deals.list_stages(%{org: org})) == 6
    end
  end

  describe "get_organization_by_slug/1" do
    test "returns the org for a known slug" do
      org = org_fixture()
      assert Accounts.get_organization_by_slug(org.slug).id == org.id
    end

    test "returns nil for unknown slug" do
      assert Accounts.get_organization_by_slug("does-not-exist") == nil
    end
  end

  describe "register_user_with_org/1" do
    test "creates user, org, and owner membership atomically" do
      email = unique_user_email()
      slug = unique_org_slug()

      assert {:ok, %{user: user, org: org, membership: membership}} =
               Accounts.register_user_with_org(%{
                 "email" => email,
                 "org_name" => "Test Co",
                 "org_slug" => slug
               })

      assert user.email == email
      assert org.slug == slug
      assert membership.role == :owner
      assert membership.user_id == user.id
      assert membership.organization_id == org.id
      assert length(Deals.list_stages(%{org: org})) == 6
    end

    test "rolls back everything if org slug is taken" do
      slug = unique_org_slug()
      org_fixture(%{slug: slug})

      assert {:error, :org, cs, _} =
               Accounts.register_user_with_org(%{
                 "email" => unique_user_email(),
                 "org_name" => "Dup",
                 "org_slug" => slug
               })

      assert %{slug: [_]} = errors_on(cs)
    end

    test "reuses an existing user for a new organization" do
      user = user_fixture()
      slug = unique_org_slug()

      assert {:ok, %{user: returned_user, org: org, membership: membership}} =
               Accounts.register_user_with_org(%{
                 "email" => user.email,
                 "org_name" => "New Org",
                 "org_slug" => slug
               })

      assert returned_user.id == user.id
      assert org.slug == slug
      assert membership.user_id == user.id
      assert membership.organization_id == org.id
      assert membership.role == :owner
    end
  end

  describe "register_user_with_default_org/1" do
    test "adds a new user to the default public organization" do
      org = org_fixture(%{name: "Public", slug: "public"})
      email = unique_user_email()

      assert {:ok, %{user: user, org: returned_org, membership: membership}} =
               Accounts.register_user_with_default_org(%{"email" => email})

      assert user.email == email
      assert returned_org.id == org.id
      assert membership.organization_id == org.id
      assert membership.user_id == user.id
      assert membership.role == :member
    end

    test "creates the default public organization when it is missing" do
      email = unique_user_email()

      assert {:ok, %{user: user, org: org, membership: membership}} =
               Accounts.register_user_with_default_org(%{"email" => email})

      assert user.email == email
      assert org.name == "Public"
      assert org.slug == "public"
      assert membership.organization_id == org.id
      assert membership.user_id == user.id
      assert membership.role == :member
    end
  end

  describe "password registration" do
    test "creates a password-protected owner account with a workspace" do
      email = unique_user_email()
      password = valid_user_password()
      slug = unique_org_slug()

      assert {:ok, %{user: user, org: org, membership: membership}} =
               Accounts.register_password_user_with_org(%{
                 "email" => email,
                 "password" => password,
                 "password_confirmation" => password,
                 "org_name" => "Test Co",
                 "org_slug" => slug
               })

      assert Accounts.get_user_by_email_and_password(email, password).id == user.id
      assert org.slug == slug
      assert membership.role == :owner
    end

    test "rejects an existing email without creating a workspace" do
      user = user_fixture()
      password = valid_user_password()
      slug = unique_org_slug()

      assert {:error, :user, changeset, _changes} =
               Accounts.register_password_user_with_org(%{
                 "email" => user.email,
                 "password" => password,
                 "password_confirmation" => password,
                 "org_name" => "Test Co",
                 "org_slug" => slug
               })

      assert %{email: [_]} = errors_on(changeset)
      assert Accounts.get_organization_by_slug(slug) == nil
    end

    test "adds a password user to the default workspace" do
      org = org_fixture(%{name: "Public", slug: "public"})
      email = unique_user_email()
      password = valid_user_password()

      assert {:ok, %{user: user, org: returned_org, membership: membership}} =
               Accounts.register_password_user_with_default_org(%{
                 "email" => email,
                 "password" => password,
                 "password_confirmation" => password
               })

      assert Accounts.get_user_by_email_and_password(email, password).id == user.id
      assert returned_org.id == org.id
      assert membership.role == :member
    end

    test "creates the private deployment owner in the default workspace" do
      org = org_fixture(%{name: "Public", slug: "public"})
      email = unique_user_email()
      password = valid_user_password()

      assert {:ok, %{user: user, org: returned_org, membership: membership}} =
               Accounts.register_password_owner_with_default_org(%{
                 "email" => email,
                 "password" => password,
                 "password_confirmation" => password
               })

      assert Accounts.get_user_by_email_and_password(email, password).id == user.id
      assert returned_org.id == org.id
      assert membership.role == :owner
    end
  end

  describe "create_membership/3" do
    test "adds user to org with given role" do
      user = user_fixture()
      org = org_fixture()
      assert {:ok, %Membership{role: :member}} = Accounts.create_membership(user, org, :member)
    end

    test "defaults to member role" do
      user = user_fixture()
      org = org_fixture()
      assert {:ok, %Membership{role: :member}} = Accounts.create_membership(user, org)
    end

    test "rejects duplicate memberships" do
      %{user: user, org: org} = user_with_org_fixture()
      assert {:error, cs} = Accounts.create_membership(user, org, :viewer)
      assert %{user_id: [_]} = errors_on(cs)
    end
  end

  describe "update_membership/2" do
    test "changes the role" do
      %{user: user, org: org, membership: membership} = user_with_org_fixture(:member)
      assert {:ok, updated} = Accounts.update_membership(membership, %{role: :admin})
      assert updated.role == :admin
      # Role change revokes sessions — user can no longer use old tokens
      assert Accounts.get_user_by_session_token("fake_token") == nil
      _ = user
      _ = org
    end

    test "rejects invalid role" do
      %{membership: membership} = user_with_org_fixture()
      assert {:error, cs} = Accounts.update_membership(membership, %{role: :superuser})
      assert %{role: [_]} = errors_on(cs)
    end
  end

  describe "list_members/1" do
    test "returns all members preloaded with user" do
      %{org: org} = user_with_org_fixture(:owner)
      extra_user = user_fixture()
      Accounts.create_membership(extra_user, org, :member)

      members = Accounts.list_members(org)
      assert length(members) == 2
      assert Enum.all?(members, &match?(%{user: %Accounts.User{}}, &1))
    end

    test "does not return members from a different org" do
      %{org: org1} = user_with_org_fixture()
      %{org: _org2} = user_with_org_fixture()

      assert length(Accounts.list_members(org1)) == 1
    end

    test "returns paginated members with total count" do
      %{org: org} = user_with_org_fixture(:owner)

      for n <- 1..3 do
        user = user_fixture(%{email: "paged-#{n}@example.com"})
        Accounts.create_membership(user, org, :member)
      end

      {members, total} = Accounts.list_members(org, page: 2, per_page: 2)

      assert length(members) == 2
      assert total == 4
      assert Enum.all?(members, &match?(%{user: %Accounts.User{}}, &1))
    end

    test "searches members by email and role" do
      %{org: org} = user_with_org_fixture(:owner)
      admin = user_fixture(%{email: "admin-search@example.com"})
      viewer = user_fixture(%{email: "viewer-search@example.com"})
      Accounts.create_membership(admin, org, :admin)
      Accounts.create_membership(viewer, org, :viewer)

      {email_results, 1} = Accounts.list_members(org, search: "admin-search")
      {role_results, 1} = Accounts.list_members(org, search: "viewer")

      assert hd(email_results).user.email == "admin-search@example.com"
      assert hd(role_results).role == :viewer
    end
  end

  describe "tenant invitations" do
    test "creates a pending tenant and seeds it when its new owner accepts" do
      owner = user_fixture()
      public_org = org_fixture(%{name: "Public", slug: "public"})
      {:ok, membership} = Accounts.create_membership(owner, public_org, :owner)
      scope = Scope.for_user_in_org(owner, public_org, membership)
      email = unique_user_email()
      slug = unique_org_slug()

      assert {:ok, %{organization: org, invitation: invitation}} =
               Accounts.create_tenant_invitation(
                 scope,
                 %{"name" => "Acme", "slug" => slug, "email" => email},
                 fn _organization, token ->
                   send(self(), {:tenant_invitation_token, token})
                   "https://#{slug}.example.com/tenant-invitations/#{token}"
                 end
               )

      assert_receive {:tenant_invitation_token, token}
      assert invitation.organization.id == org.id
      assert Deals.list_stages(%{org: org}) == []
      assert [found_invitation] = Accounts.list_tenant_invitations(search: "Acme")
      assert found_invitation.id == invitation.id
      assert Accounts.list_tenant_invitations(search: "no-match") == []

      assert {:ok, %{user: user, organization: accepted_org, membership: accepted_membership}} =
               Accounts.accept_tenant_invitation(token, %{
                 "password" => valid_user_password(),
                 "password_confirmation" => valid_user_password()
               })

      assert user.email == email
      assert accepted_org.id == org.id
      assert accepted_membership.role == :owner
      assert Accounts.get_user_by_email_and_password(email, valid_user_password()).id == user.id
      assert length(Deals.list_stages(%{org: org})) == 6
      assert Repo.get!(TenantInvitation, invitation.id).accepted_at
      assert Accounts.get_tenant_invitation(token) == nil
    end

    test "attaches an existing password account without creating a second user" do
      main_owner = user_fixture()
      public_org = org_fixture(%{name: "Public", slug: "public"})
      {:ok, membership} = Accounts.create_membership(main_owner, public_org, :owner)
      scope = Scope.for_user_in_org(main_owner, public_org, membership)
      existing_user = user_fixture() |> set_password()
      slug = unique_org_slug()

      assert {:ok, %{organization: org}} =
               Accounts.create_tenant_invitation(
                 scope,
                 %{"name" => "Existing User Org", "slug" => slug, "email" => existing_user.email},
                 fn _organization, token ->
                   send(self(), {:existing_user_invitation_token, token})
                   "https://#{slug}.example.com/tenant-invitations/#{token}"
                 end
               )

      assert_receive {:existing_user_invitation_token, token}

      assert {:ok, %{user: accepted_user, membership: accepted_membership}} =
               Accounts.accept_tenant_invitation(token, %{"password" => valid_user_password()})

      assert accepted_user.id == existing_user.id
      assert accepted_membership.user_id == existing_user.id
      assert accepted_membership.organization_id == org.id
      assert accepted_membership.role == :owner
    end

    test "allows only the default tenant owner to create tenant invitations" do
      user = user_fixture()
      org = org_fixture()
      {:ok, membership} = Accounts.create_membership(user, org, :owner)
      scope = Scope.for_user_in_org(user, org, membership)

      assert {:error, :unauthorized} =
               Accounts.create_tenant_invitation(
                 scope,
                 %{
                   "name" => "Blocked",
                   "slug" => unique_org_slug(),
                   "email" => unique_user_email()
                 },
                 fn _organization, token -> "https://example.com/#{token}" end
               )
    end

    test "archives and restores a tenant, blocking invitation acceptance while archived" do
      owner = user_fixture()
      public_org = org_fixture(%{name: "Public", slug: "public"})
      {:ok, membership} = Accounts.create_membership(owner, public_org, :owner)
      scope = Scope.for_user_in_org(owner, public_org, membership)
      slug = unique_org_slug()

      assert {:ok, %{invitation: invitation}} =
               Accounts.create_tenant_invitation(
                 scope,
                 %{"name" => "Archive Acme", "slug" => slug, "email" => unique_user_email()},
                 fn _organization, token ->
                   send(self(), {:archived_tenant_invitation_token, token})
                   "https://#{slug}.example.com/tenant-invitations/#{token}"
                 end
               )

      assert_receive {:archived_tenant_invitation_token, token}
      assert {:ok, archived} = Accounts.archive_tenant(scope, invitation.id)
      assert archived.organization.archived_at
      refute Accounts.organization_active?(archived.organization)
      assert Accounts.get_tenant_invitation(token) == nil
      assert {:error, :invalid_or_expired} = Accounts.accept_tenant_invitation(token, %{})

      assert {:ok, restored} = Accounts.restore_tenant(scope, invitation.id)
      assert restored.organization.archived_at == nil
      assert Accounts.organization_active?(restored.organization)
      assert Accounts.get_tenant_invitation(token).id == invitation.id
    end
  end

  describe "delete_membership/1" do
    test "removes the membership" do
      %{org: org} = user_with_org_fixture(:owner)
      extra_user = user_fixture()
      {:ok, membership} = Accounts.create_membership(extra_user, org, :member)

      assert {:ok, _} = Accounts.delete_membership(membership)
      assert length(Accounts.list_members(org)) == 1
    end
  end
end
