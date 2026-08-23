defmodule Konevo.Workers.UploadDeleteCleanupWorker do
  @moduledoc """
  Retries physical cleanup for uploaded files that were logically deleted.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Konevo.Uploads

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Uploads.cleanup_deleted_files()
    :ok
  end
end
