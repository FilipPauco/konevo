defmodule Konevo.Uploads.NoopScanner do
  @moduledoc """
  No-op malware scanner implementation.

  This is the default scanner and always returns :clean.
  Use this to remember that no actual scanning is enabled.

  To enable real scanning (e.g., ClamAV), update the app config:
    config :konevo, :malware_scanner, Konevo.Uploads.ClamAVScanner
  """

  @behaviour Konevo.Uploads.MalwareScanner

  require Logger

  @impl true
  def scan(file_path) when is_binary(file_path) do
    Logger.warning("[Uploads] Malware scanning is disabled. File uploaded: #{file_path}")
    :clean
  end
end
