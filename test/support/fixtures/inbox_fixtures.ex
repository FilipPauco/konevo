defmodule Konevo.InboxFixtures do
  @moduledoc """
  ExMachina-based helpers for creating Inbox entities in tests.
  Always pass a `scope` so records are correctly org-scoped.
  """

  import Konevo.Factory

  def integration_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{organization: scope.org, user: scope.user})

    insert(:email_integration, attrs)
  end

  def thread_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{organization: scope.org})

    insert(:email_thread, attrs)
  end

  def email_fixture(scope, thread, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{organization: scope.org, thread: thread})

    insert(:email, attrs)
  end
end
