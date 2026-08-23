defmodule Konevo.Workers.ScheduledEmailWorkerTest do
  use Konevo.DataCase, async: true

  import Konevo.Factory

  alias Konevo.Inbox.ScheduledEmail
  alias Konevo.Repo
  alias Konevo.Workers.ScheduledEmailRecoveryWorker
  alias Konevo.Workers.ScheduledEmailWorker

  describe "perform/1" do
    test "does nothing for cancelled scheduled emails" do
      scheduled_email = insert(:scheduled_email, status: :cancelled)

      assert :ok =
               perform_worker(scheduled_email)

      reloaded = Repo.get!(ScheduledEmail, scheduled_email.id)
      assert reloaded.status == :cancelled
      assert is_nil(reloaded.sent_at)
    end

    test "does nothing for already sent scheduled emails" do
      sent_at = DateTime.add(DateTime.utc_now(:second), -60)
      scheduled_email = insert(:scheduled_email, status: :sent, sent_at: sent_at)

      assert :ok =
               perform_worker(scheduled_email)

      reloaded = Repo.get!(ScheduledEmail, scheduled_email.id)
      assert reloaded.status == :sent
      assert reloaded.sent_at == DateTime.truncate(sent_at, :second)
    end

    test "keeps pending scheduled emails retryable before the final attempt" do
      scheduled_email = insert(:scheduled_email)

      assert {:error, :no_integration} =
               perform_worker(scheduled_email, attempt: 1, max_attempts: 5)

      reloaded = Repo.get!(ScheduledEmail, scheduled_email.id)
      assert reloaded.status == :pending
      assert is_nil(reloaded.failed_at)
    end

    test "marks pending scheduled emails failed on the final attempt" do
      scheduled_email = insert(:scheduled_email)

      assert {:error, :no_integration} =
               perform_worker(scheduled_email, attempt: 5, max_attempts: 5)

      reloaded = Repo.get!(ScheduledEmail, scheduled_email.id)
      assert reloaded.status == :failed
      assert %DateTime{} = reloaded.failed_at
      assert reloaded.failure_reason =~ "no_integration"
    end
  end

  describe "recovery perform/1" do
    test "processes overdue pending scheduled emails" do
      due_at = DateTime.add(DateTime.utc_now(:second), -60, :second)
      future_at = DateTime.add(DateTime.utc_now(:second), 3600, :second)
      due = insert(:scheduled_email, scheduled_at: due_at)
      future = insert(:scheduled_email, scheduled_at: future_at)

      assert :ok = ScheduledEmailRecoveryWorker.perform(%Oban.Job{})

      assert Repo.get!(ScheduledEmail, due.id).status == :failed
      assert Repo.get!(ScheduledEmail, future.id).status == :pending
    end
  end

  defp perform_worker(scheduled_email, opts \\ []) do
    ScheduledEmailWorker.perform(%Oban.Job{
      attempt: Keyword.get(opts, :attempt, 1),
      max_attempts: Keyword.get(opts, :max_attempts, 5),
      args: %{"scheduled_email_id" => scheduled_email.id}
    })
  end
end
