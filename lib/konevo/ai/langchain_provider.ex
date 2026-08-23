defmodule Konevo.AI.LangChainProvider do
  @moduledoc false
  @behaviour Konevo.AI.Provider

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAIResponses
  alias LangChain.Message
  alias LangChain.Message.ContentPart

  @impl true
  def complete(messages, %{provider: provider, model: model} = settings) do
    with {:ok, llm} <- build_model(provider, model, settings),
         {:ok, chain} <- run_chain(llm, messages, []),
         {:ok, content} <- response_content(chain.last_message) do
      {:ok,
       %{
         content: content,
         model: model,
         provider: Atom.to_string(provider),
         usage: usage_from(chain.last_message)
       }}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  @impl true
  def stream_complete(messages, %{provider: provider, model: model} = settings, chunk_fun)
      when is_function(chunk_fun, 1) do
    with {:ok, llm} <- build_model(provider, model, settings, true),
         {:ok, chain} <- run_chain(llm, messages, [stream_callback(chunk_fun)]),
         {:ok, content} <- response_content(chain.last_message) do
      {:ok,
       %{
         content: content,
         model: model,
         provider: Atom.to_string(provider),
         usage: usage_from(chain.last_message)
       }}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp build_model(provider, model, settings, stream \\ false)

  defp build_model(:openai_responses, model, %{api_key: api_key} = settings, stream)
       when is_binary(api_key) do
    ChatOpenAIResponses.new(
      %{api_key: api_key, model: model, stream: stream}
      |> Map.merge(Map.take(settings, [:reasoning]))
    )
  end

  defp build_model(:openai_responses, _model, _settings, _stream),
    do: {:error, :missing_openai_api_key}

  defp build_model(_provider, _model, _settings, _stream), do: {:error, :unsupported_provider}

  defp run_chain(llm, messages, callbacks) do
    chain =
      %{llm: llm, verbose: false}
      |> LLMChain.new!()
      |> LLMChain.add_messages(Enum.map(messages, &to_message/1))

    chain = Enum.reduce(callbacks, chain, &LLMChain.add_callback(&2, &1))

    case LLMChain.run(chain) do
      {:ok, updated_chain} -> {:ok, updated_chain}
      {:error, _chain, reason} -> {:error, reason}
    end
  end

  defp stream_callback(chunk_fun) do
    %{
      on_llm_new_delta: fn _chain, deltas ->
        deltas
        |> Enum.map(&delta_content/1)
        |> Enum.filter(&(is_binary(&1) and &1 != ""))
        |> Enum.each(chunk_fun)
      end
    }
  end

  defp to_message(%{role: :system, content: content}), do: Message.new_system!(content)
  defp to_message(%{role: :assistant, content: content}), do: Message.new_assistant!(content)
  defp to_message(%{content: content}), do: Message.new_user!(content)

  defp response_content(%{content: content}) when is_list(content) do
    case ContentPart.parts_to_string(content) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :empty_response}
    end
  end

  defp response_content(%{content: content}) when is_binary(content) and content != "",
    do: {:ok, content}

  defp response_content(_message), do: {:error, :empty_response}

  defp delta_content(%{content: content}) when is_binary(content), do: content

  defp delta_content(%{content: %ContentPart{} = part}) do
    case ContentPart.parts_to_string([part]) do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp delta_content(_delta), do: ""

  defp usage_from(%{metadata: metadata}) when is_map(metadata) do
    usage = Map.get(metadata, :usage) || Map.get(metadata, "usage") || %{}

    %{
      input: Map.get(usage, :input) || Map.get(usage, "input"),
      output: Map.get(usage, :output) || Map.get(usage, "output")
    }
  end

  defp usage_from(_message), do: %{}
end
