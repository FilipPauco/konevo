defmodule Konevo.Workers.ApprovalExpiryWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Konevo.Automation

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, _totals} = Automation.expire_pending_approvals()
    :ok
  end
end
