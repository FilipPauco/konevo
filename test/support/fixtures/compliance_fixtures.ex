defmodule Konevo.ComplianceFixtures do
  @moduledoc """
  ExMachina-based helpers for creating Compliance entities in tests.
  """

  import Konevo.Factory

  def consent_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{organization: scope.org, contact: contact_for(scope)})

    insert(:consent, attrs)
  end

  def suppression_entry_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{organization: scope.org})

    insert(:suppression_entry, attrs)
  end

  def audit_log_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{organization: scope.org, actor: scope.user})

    insert(:audit_log, attrs)
  end

  defp contact_for(scope) do
    insert(:contact, organization: scope.org, user: scope.user)
  end
end
