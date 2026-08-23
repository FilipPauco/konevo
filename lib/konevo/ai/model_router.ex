defmodule Konevo.AI.ModelRouter do
  @moduledoc false

  alias Konevo.Accounts.Scope

  @task_tiers %{
    entity_extraction: :fast,
    reply_draft: :standard,
    company_research: :premium
  }

  def complete(%Scope{} = scope, task, messages) when is_list(messages) do
    with {:ok, model} <- route(task),
         model <- with_scope_api_key(scope, model),
         provider when is_atom(provider) <- Application.fetch_env!(:konevo, :ai)[:provider] do
      provider.complete(messages, model)
    else
      {:error, _reason} = error -> error
      _ -> {:error, :provider_not_configured}
    end
  end

  def complete(task, messages) when is_list(messages) do
    with {:ok, model} <- route(task),
         provider when is_atom(provider) <- Application.fetch_env!(:konevo, :ai)[:provider] do
      provider.complete(messages, model)
    else
      {:error, _reason} = error -> error
      _ -> {:error, :provider_not_configured}
    end
  end

  def stream_complete(%Scope{} = scope, task, messages, chunk_fun)
      when is_list(messages) and is_function(chunk_fun, 1) do
    with {:ok, model} <- route(task),
         model <- with_scope_api_key(scope, model),
         provider when is_atom(provider) <- Application.fetch_env!(:konevo, :ai)[:provider] do
      if function_exported?(provider, :stream_complete, 3) do
        provider.stream_complete(messages, model, chunk_fun)
      else
        provider.complete(messages, model)
      end
    else
      {:error, _reason} = error -> error
      _ -> {:error, :provider_not_configured}
    end
  end

  def stream_complete(task, messages, chunk_fun)
      when is_list(messages) and is_function(chunk_fun, 1) do
    with {:ok, model} <- route(task),
         provider when is_atom(provider) <- Application.fetch_env!(:konevo, :ai)[:provider] do
      if function_exported?(provider, :stream_complete, 3) do
        provider.stream_complete(messages, model, chunk_fun)
      else
        provider.complete(messages, model)
      end
    else
      {:error, _reason} = error -> error
      _ -> {:error, :provider_not_configured}
    end
  end

  def route(task) when is_atom(task) do
    config = Application.fetch_env!(:konevo, :ai)
    tier = Map.get(@task_tiers, task, :standard)

    case get_in(config, [:models, tier]) do
      %{model: model} = settings when is_binary(model) and model != "" ->
        {:ok, Map.put(settings, :task, task)}

      _ ->
        {:error, :model_not_configured}
    end
  end

  def route(_task), do: {:error, :invalid_task}

  defp with_scope_api_key(%Scope{} = scope, %{provider: provider} = settings) do
    case Konevo.AI.fetch_provider_api_key(scope, provider) do
      {:ok, api_key} -> Map.put(settings, :api_key, api_key)
      {:error, _reason} -> settings
    end
  end
end
