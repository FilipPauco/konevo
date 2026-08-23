defmodule Konevo.Workers.GmailSyncWorker do
  @moduledoc """
  Oban worker that keeps active Gmail integrations recently synced.

  Historical imports are handled by `Konevo.Workers.GmailBackfillWorker`.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  import Ecto.Query, warn: false

  alias Konevo.Inbox.{EmailIntegration, GmailImporter}
  alias Konevo.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"integration_id" => id}}) do
    case Repo.get(EmailIntegration, id) do
      nil ->
        Logger.warning("GmailSyncWorker: integration #{id} not found, skipping")
        :ok

      integration ->
        sync_integration(integration)
    end
  end

  def perform(%Oban.Job{}) do
    EmailIntegration
    |> where(provider: :gmail, sync_enabled: true)
    |> Repo.all()
    |> Enum.each(&sync_integration/1)

    :ok
  end

  defp sync_integration(%EmailIntegration{} = integration) do
    case GmailImporter.sync_recent(integration) do
      {:ok, %{processed: processed} = result} ->
        Logger.info(
          "GmailSyncWorker: synced #{processed} threads for integration #{integration.id}"
        )

        broadcast_sync_finished(integration, {:ok, result})
        :ok

      {:error, reason} ->
        Logger.error(
          "GmailSyncWorker: sync failed for integration #{integration.id}: #{inspect(reason)}"
        )

        broadcast_sync_finished(integration, {:error, reason})
        {:error, reason}
    end
  end

  defp broadcast_sync_finished(%EmailIntegration{} = integration, result) do
    Phoenix.PubSub.broadcast(
      Konevo.PubSub,
      gmail_sync_topic(integration.organization_id),
      {:gmail_sync_finished, %{integration_id: integration.id, result: result}}
    )
  end

  defp gmail_sync_topic(org_id), do: "inbox:gmail_sync:#{org_id}"
end
