defmodule Konevo.AutomationFixtures do
  @moduledoc """
  ExMachina-based helpers for creating Automation entities in tests.
  """

  import Konevo.Factory

  def sequence_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{organization: scope.org, created_by: scope.user})

    insert(:automation_sequence, attrs)
  end

  def rule_fixture(scope, sequence, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{organization: scope.org, sequence: sequence})

    insert(:automation_rule, attrs)
  end

  def execution_fixture(scope, sequence, contact, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{organization: scope.org, sequence: sequence, contact: contact})

    insert(:automation_execution, attrs)
  end
end
