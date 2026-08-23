defmodule Konevo.Workers.ScheduledEmailWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 5

  alias Konevo.Inbox

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"scheduled_email_id" => scheduled_email_id}} = job) do
    case Inbox.deliver_scheduled_email(scheduled_email_id, mark_failed?: final_attempt?(job)) do
      {:ok, _result} -> :ok
      {:error, _reason} = error -> error
    end
  end

  def perform(%Oban.Job{}), do: :ok

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    [60, 300, 900, 1_800]
    |> Enum.at(attempt - 1, 3_600)
  end

  defp final_attempt?(%Oban.Job{attempt: attempt, max_attempts: max_attempts}) do
    attempt >= max_attempts
  end
end
