defmodule Konevo.CompaniesFixtures do
  @moduledoc false

  import Konevo.Factory

  def company_fixture(scope, attrs \\ %{}) do
    attrs = attrs |> Enum.into(%{}) |> Map.merge(%{user: scope.user, organization: scope.org})
    insert(:company, attrs)
  end
end
