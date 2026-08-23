defmodule Konevo.Uploads.PathTraversalError do
  @moduledoc """
  Exception raised when a path traversal attack or invalid path segment is detected.
  """
  defexception [:message]

  @impl true
  def exception(msg) when is_binary(msg) do
    %__MODULE__{message: msg}
  end

  def exception(opts) when is_list(opts) do
    message = opts[:message] || "Invalid path segment"
    %__MODULE__{message: message}
  end
end
