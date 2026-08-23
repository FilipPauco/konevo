defmodule Konevo.Workers.GmailBackfillWorker do
  @moduledoc """
  Oban worker for user-triggered historical Gmail imports.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  alias Konevo.Inbox.{EmailIntegration, GmailImporter}
  alias Konevo.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "integration_id" => integration_id,
          "query" => query
        }
      }) do
    case Repo.get(EmailIntegration, integration_id) do
      %EmailIntegration{provider: :gmail, sync_enabled: true} = integration ->
        mark_started(integration)
        import_history(integration, query)

      %EmailIntegration{provider: :gmail} = integration ->
        mark_failed(integration, :gmail_reauthorization_required)
        {:error, :gmail_reauthorization_required}

      _ ->
        :ok
    end
  end

  def perform(%Oban.Job{}), do: :ok

  def build_query(%{"mode" => "all"}) do
    {:ok, "-in:trash -in:spam"}
  end

  def build_query(%{"mode" => "since", "start_date" => start_date}) do
    with {:ok, start_date} <- parse_date(start_date) do
      {:ok, gmail_search(start_date, nil)}
    end
  end

  def build_query(%{"mode" => "between", "start_date" => start_date, "end_date" => end_date}) do
    with {:ok, start_date} <- parse_date(start_date),
         {:ok, end_date} <- parse_date(end_date),
         :ok <- validate_range(start_date, end_date) do
      {:ok, gmail_search(start_date, end_date)}
    end
  end

  def build_query(_params), do: {:error, :invalid_backfill_range}

  defp import_history(%EmailIntegration{} = integration, query) do
    case GmailImporter.import_history(integration, query) do
      {:ok, %{imported: imported, processed: processed}} ->
        Logger.info(
          "GmailBackfillWorker: imported #{imported} new threads and refreshed #{processed - imported} threads for integration #{integration.id}"
        )

        mark_completed(integration, imported, processed)

      {:error, reason} ->
        Logger.error(
          "GmailBackfillWorker: import failed for integration #{integration.id}: #{inspect(reason)}"
        )

        mark_failed(integration, reason)
        {:error, reason}
    end
  end

  defp mark_started(integration) do
    update_history_import(integration, %{
      history_import_status: "running",
      history_import_started_at: DateTime.utc_now(:second),
      history_import_completed_at: nil,
      history_import_error: nil
    })
  end

  defp mark_completed(integration, imported, processed) do
    update_history_import(integration, %{
      history_import_status: "completed",
      history_import_completed_at: DateTime.utc_now(:second),
      history_imported_threads: imported,
      history_processed_threads: processed,
      history_import_error: nil
    })
  end

  defp mark_failed(integration, reason) do
    update_history_import(integration, %{
      history_import_status: "failed",
      history_import_completed_at: DateTime.utc_now(:second),
      history_import_error: inspect(reason)
    })
  end

  defp update_history_import(integration, attrs) do
    integration
    |> EmailIntegration.history_import_changeset(attrs)
    |> Repo.update()
  end

  defp gmail_search(start_date, nil) do
    [gmail_filter("after", start_date), "-in:trash", "-in:spam"]
    |> Enum.join(" ")
  end

  defp gmail_search(start_date, end_date) do
    inclusive_end = Date.add(end_date, 1)

    [
      gmail_filter("after", start_date),
      gmail_filter("before", inclusive_end),
      "-in:trash",
      "-in:spam"
    ]
    |> Enum.join(" ")
  end

  defp gmail_filter(operator, %Date{} = date) when operator in ["after", "before"] do
    [operator, gmail_date(date)]
    |> Enum.join(":")
  end

  defp gmail_date(%Date{} = date) do
    Calendar.strftime(date, "%Y/%m/%d")
  end

  defp parse_date(value) when is_binary(value) do
    value = String.trim(value)

    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, :invalid_backfill_range}
    end
  end

  defp parse_date(_value), do: {:error, :invalid_backfill_range}

  defp validate_range(start_date, end_date) do
    if Date.compare(start_date, end_date) == :gt do
      {:error, :invalid_backfill_range}
    else
      :ok
    end
  end
end
