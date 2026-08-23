defmodule Konevo.AI.Provider do
  @moduledoc """
  Project-owned boundary around LLM providers.
  """

  @callback complete([map()], map()) ::
              {:ok, %{content: String.t(), model: String.t(), provider: String.t(), usage: map()}}
              | {:error, term()}

  @callback stream_complete([map()], map(), (String.t() -> any())) ::
              {:ok, %{content: String.t(), model: String.t(), provider: String.t(), usage: map()}}
              | {:error, term()}

  @optional_callbacks stream_complete: 3
end
