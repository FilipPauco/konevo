defmodule Konevo.ContactsFixtures do
  @moduledoc """
  ExMachina-based helpers for creating Contact entities in tests.
  Always pass a `scope` so the contact is correctly org-scoped.
  """

  import Konevo.Factory

  @doc """
  Inserts a contact belonging to the given scope's user and org.
  Pass `attrs` to override any factory default (e.g. `%{status: :customer}`).
  """
  def contact_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{user: scope.user, organization: scope.org})

    insert(:contact, attrs)
  end
end
