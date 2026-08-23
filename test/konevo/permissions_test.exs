defmodule Konevo.PermissionsTest do
  use Konevo.DataCase, async: true

  import Konevo.AccountsFixtures

  alias Konevo.Permissions

  setup do
    %{user: user, org: org, membership: _} = user_with_org_fixture(:owner)
    other_user = user_fixture()
    %{user: user, org: org, other_user: other_user}
  end

  describe "can?/4" do
    for {role, resource, action, expected} <- [
          {:owner, :contacts, :create, true},
          {:owner, :contacts, :delete, true},
          {:owner, :reports, :delete, true},
          {:admin, :contacts, :create, true},
          {:admin, :contacts, :delete, true},
          {:admin, :reports, :delete, false},
          {:member, :contacts, :read, true},
          {:member, :contacts, :create, true},
          {:member, :contacts, :update, true},
          {:member, :contacts, :delete, false},
          {:member, :tasks, :delete, true},
          {:member, :companies, :create, true},
          {:member, :automation, :create, true},
          {:member, :automation, :update, true},
          {:member, :automation, :delete, false},
          {:member, :reports, :read, false},
          {:viewer, :contacts, :read, true},
          {:viewer, :contacts, :create, false},
          {:viewer, :contacts, :delete, false}
        ] do
      test "#{role} can#{if expected, do: "", else: " not"} #{action} #{resource}" do
        %{user: user, org: org} = user_with_org_fixture(unquote(role))

        assert Permissions.can?(user, org, unquote(resource), unquote(action)) ==
                 unquote(expected)
      end
    end

    test "returns false when user has no membership in org" do
      %{other_user: other_user, org: org} = setup_for_context()
      refute Permissions.can?(other_user, org, :contacts, :read)
    end

    test "custom_permissions grant access beyond role" do
      %{user: user, org: org} = user_with_org_fixture(:viewer)
      membership = Permissions.get_membership(user, org)

      Konevo.Accounts.update_membership(membership, %{
        custom_permissions: ["contacts:create"]
      })

      assert Permissions.can?(user, org, :contacts, :create)
    end
  end

  describe "can?/3" do
    test "checks permissions from a loaded membership" do
      %{membership: membership} = user_with_org_fixture(:viewer)

      assert Permissions.can?(membership, :automation, :read)
      refute Permissions.can?(membership, :automation, :create)
    end
  end

  describe "has_role?/3" do
    test "owner satisfies any role requirement" do
      %{user: user, org: org} = user_with_org_fixture(:owner)
      assert Permissions.has_role?(user, org, :owner)
      assert Permissions.has_role?(user, org, :admin)
      assert Permissions.has_role?(user, org, :member)
      assert Permissions.has_role?(user, org, :viewer)
    end

    test "member does not satisfy admin or owner" do
      %{user: user, org: org} = user_with_org_fixture(:member)
      refute Permissions.has_role?(user, org, :admin)
      refute Permissions.has_role?(user, org, :owner)
      assert Permissions.has_role?(user, org, :member)
      assert Permissions.has_role?(user, org, :viewer)
    end

    test "returns false for user with no membership" do
      %{other_user: other_user, org: org} = setup_for_context()
      refute Permissions.has_role?(other_user, org, :viewer)
    end
  end

  describe "get_membership/2" do
    test "returns the membership when found" do
      %{user: user, org: org, membership: membership} = user_with_org_fixture()
      assert Permissions.get_membership(user, org).id == membership.id
    end

    test "returns nil when not a member" do
      %{other_user: other_user, org: org} = setup_for_context()
      assert Permissions.get_membership(other_user, org) == nil
    end
  end

  # Helper to access the outer setup data inside per-test helpers
  defp setup_for_context do
    user = user_fixture()
    other_user = user_fixture()
    %{user: user, org: org_fixture(), other_user: other_user}
  end
end
