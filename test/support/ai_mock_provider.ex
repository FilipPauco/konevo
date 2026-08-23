defmodule Konevo.AIMockProvider do
  @moduledoc false
  @behaviour Konevo.AI.Provider

  @impl true
  def complete(messages, settings) do
    if pid = Map.get(settings, :test_pid) do
      send(pid, {:ai_complete, Map.get(settings, :task), messages})
    end

    case Map.get(settings, :response) do
      {:error, reason} ->
        {:error, reason}

      response when is_binary(response) ->
        {:ok,
         %{
           content: response,
           model: Map.fetch!(settings, :model),
           provider: "mock",
           usage: %{input: 1, output: 1}
         }}
    end
  end
end
