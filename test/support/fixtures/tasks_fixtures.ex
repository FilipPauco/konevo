defmodule Konevo.TasksFixtures do
  @moduledoc """
  ExMachina-based helpers for creating Task entities in tests.
  Always pass a `scope` so the task is correctly org-scoped.
  """

  import Konevo.Factory

  def task_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{
        organization: scope.org,
        created_by: scope.user
      })

    insert(:task, attrs)
  end
end
