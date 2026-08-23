defmodule Konevo.Workers.ScheduledEmailRecoveryWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Konevo.Inbox

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Inbox.deliver_due_scheduled_emails()
    :ok
  end
end
