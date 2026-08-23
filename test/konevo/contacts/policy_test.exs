defmodule Konevo.Contacts.PolicyTest do
  use Konevo.DataCase, async: true

  import Konevo.Factory

  alias Konevo.Contacts.Contact
  alias Konevo.Contacts.Policy

  setup do
    user = insert(:user)
    org = insert(:organization)
    %{user: user, org: org}
  end

  # Build a minimal contact struct — Policy never queries the DB for it.
  defp contact_params(org), do: %{org: org, contact: %Contact{}}

  # ---------------------------------------------------------------------------
  # Parametrized permission matrix
  # Each row: {role, action, expected_authorized?}
  # For delete we always pass contact_params (which also works for create/read/update
  # because Elixir map pattern matching allows extra keys).
  # ---------------------------------------------------------------------------

  for {role, action, expected} <- [
        {:owner, :create, true},
        {:owner, :read, true},
        {:owner, :update, true},
        {:owner, :delete, true},
        {:admin, :create, true},
        {:admin, :read, true},
        {:admin, :update, true},
        {:admin, :delete, true},
        {:member, :create, true},
        {:member, :read, true},
        {:member, :update, true},
        {:member, :delete, false},
        {:viewer, :create, false},
        {:viewer, :read, true},
        {:viewer, :update, false},
        {:viewer, :delete, false}
      ] do
    test "#{role} can#{if expected, do: "", else: " not"} #{action} a contact",
         %{user: user, org: org} do
      insert(:membership, user: user, organization: org, role: unquote(role))

      result = Policy.authorize(unquote(action), user, contact_params(org))

      if unquote(expected) do
        assert result == :ok
      else
        assert result == {:error, :unauthorized}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "authorize/3 edge cases" do
    test "returns unauthorized for user with no membership in org", %{user: user, org: org} do
      result = Policy.authorize(:read, user, %{org: org})
      assert result == {:error, :unauthorized}
    end

    test "returns unauthorized for unknown action", %{user: user, org: org} do
      insert(:membership, user: user, organization: org, role: :owner)
      result = Policy.authorize(:explode, user, %{org: org})
      assert result == {:error, :unauthorized}
    end
  end
end
