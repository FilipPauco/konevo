defmodule Konevo.Workers.GmailThreadReadStateWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Konevo.Inbox

  def enqueue(thread_id, read?) when is_integer(thread_id) and is_boolean(read?) do
    %{"thread_id" => thread_id, "read" => read?}
    |> new()
    |> then(&Oban.insert(Konevo.Oban, &1))
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => thread_id, "read" => read?}})
      when is_integer(thread_id) and is_boolean(read?) do
    Inbox.sync_gmail_thread_read_state(thread_id, read?)
  end

  def perform(%Oban.Job{}), do: {:error, :invalid_args}
end
