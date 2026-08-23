defmodule Konevo.DealsFixtures do
  @moduledoc """
  ExMachina-based helpers for creating Deal entities in tests.
  Always pass a `scope` so the deal is correctly org-scoped.
  """

  import Konevo.Factory

  def deal_stage_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{organization: scope.org})

    insert(:deal_stage, attrs)
  end

  def deal_fixture(scope, stage, attrs \\ %{}) do
    contact = insert(:contact, organization: scope.org, user: scope.user)

    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{
        organization: scope.org,
        contact: contact,
        stage: stage,
        owner: scope.user,
        created_by: scope.user
      })

    insert(:deal, attrs)
  end
end
