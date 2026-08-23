defmodule Konevo.MessagingFixtures do
  @moduledoc """
  ExMachina-based helpers for creating Messaging entities in tests.
  Always pass a `scope` so records are correctly org-scoped.
  """

  import Konevo.Factory

  def draft_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{organization: scope.org, created_by: scope.user})

    insert(:message_draft, attrs)
  end

  def sent_fixture(scope, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.merge(%{organization: scope.org, sent_by: scope.user})

    insert(:message_sent, attrs)
  end
end
