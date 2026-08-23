defmodule Konevo.Security.RateLimiter do
  @moduledoc """
  A bounded, in-memory fixed-window rate limiter for authentication actions.

  Identifiers are hashed before storage so the process state never retains raw
  email addresses, tokens, or IP addresses.
  """

  use GenServer

  require Logger

  @max_entries 10_000
  @limits %{
    password_login: %{email: {5, :timer.minutes(15)}, ip: {25, :timer.minutes(15)}},
    two_factor: %{user_id: {5, :timer.minutes(15)}, ip: {25, :timer.minutes(15)}},
    magic_link_login: %{token: {5, :timer.minutes(15)}, ip: {25, :timer.minutes(15)}},
    password_reset: %{token: {5, :timer.minutes(15)}, ip: {25, :timer.minutes(15)}},
    password_reset_request: %{email: {3, :timer.hours(1)}, ip: {10, :timer.hours(1)}},
    registration: %{email: {3, :timer.hours(1)}, ip: {10, :timer.hours(1)}},
    public_landing: %{ip: {30, :timer.minutes(1)}}
  }

  @type bucket ::
          :password_login
          | :two_factor
          | :magic_link_login
          | :password_reset
          | :password_reset_request
          | :registration
          | :public_landing
  @type rate_limit_identifier :: {atom(), String.t()}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Records an authentication attempt and returns `:ok` or a retry delay in seconds.
  """
  @spec check(bucket(), [rate_limit_identifier()]) :: :ok | {:error, pos_integer()}
  def check(bucket, identifiers) when is_map_key(@limits, bucket) and is_list(identifiers) do
    identifiers = Enum.filter(identifiers, &valid_identifier?(&1, bucket))
    GenServer.call(__MODULE__, {:check, bucket, identifiers})
  end

  @doc false
  def reset! do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:reset, _from, _state), do: {:reply, :ok, %{}}

  def handle_call({:check, bucket, identifiers}, _from, state) do
    now = System.monotonic_time(:millisecond)
    state = prune_expired(state, now)

    {result, state} =
      Enum.reduce_while(identifiers, {:ok, state}, fn {scope, identifier}, {:ok, state} ->
        {limit, window} = @limits[bucket][scope]
        key = {bucket, scope, hash(identifier)}
        {result, state} = increment(state, key, limit, window, now)

        case result do
          :ok -> {:cont, {:ok, state}}
          {:error, retry_after} -> {:halt, {{:error, retry_after}, state}}
        end
      end)

    log_decision(bucket, identifiers, result, state)

    {:reply, result, state}
  end

  defp increment(state, key, limit, window, now) do
    case Map.get(state, key) do
      nil when map_size(state) >= @max_entries ->
        {{:error, 60}, state}

      nil ->
        {:ok, Map.put(state, key, %{count: 1, expires_at: now + window})}

      %{expires_at: expires_at} when now >= expires_at ->
        {:ok, Map.put(state, key, %{count: 1, expires_at: now + window})}

      %{count: count} = entry when count < limit ->
        {:ok, Map.put(state, key, %{entry | count: count + 1})}

      %{expires_at: expires_at} ->
        retry_after = max(1, div(expires_at - now + 999, 1_000))
        {{:error, retry_after}, state}
    end
  end

  defp prune_expired(state, now) do
    Map.reject(state, fn {_key, %{expires_at: expires_at}} -> now >= expires_at end)
  end

  defp valid_identifier?({scope, value}, bucket) when is_atom(scope) and is_binary(value) do
    value != "" and is_map_key(@limits[bucket], scope)
  end

  defp valid_identifier?(_identifier, _bucket), do: false

  defp log_decision(bucket, identifiers, result, state) do
    counters =
      Enum.map_join(identifiers, ",", fn {scope, identifier} ->
        {limit, _window} = @limits[bucket][scope]

        count =
          state |> Map.get({bucket, scope, hash(identifier)}, %{count: 0}) |> Map.fetch!(:count)

        "#{scope}=#{count}/#{limit}"
      end)

    Logger.debug(
      "auth rate limit bucket=#{bucket} result=#{format_result(result)} counters=#{counters}"
    )
  end

  defp format_result(:ok), do: "allowed"
  defp format_result({:error, retry_after}), do: "limited retry_after=#{retry_after}s"

  defp hash(value), do: :crypto.hash(:sha256, value)
end
