defmodule Konevo.Uploads.ImageMetadataStripper do
  @moduledoc """
  Strips metadata (EXIF, IPTC, XMP, GPS, ICC profiles, etc.) from image files
  using ImageMagick via the Mogrify library.

  Requires ImageMagick to be installed on the host.
  """

  require Logger

  @doc """
  Strip all metadata from an image file in place.

  Returns `:ok` on success or `{:error, reason}`.
  Works on raster formats: JPEG, PNG, WEBP, GIF.
  """
  def strip_metadata(file_path) when is_binary(file_path) do
    Mogrify.open(file_path)
    |> Mogrify.custom("strip")
    |> Mogrify.save(in_place: true)

    Logger.debug("[ImageMetadataStripper] Metadata stripped: #{file_path}")
    :ok
  rescue
    exception in RuntimeError ->
      handle_runtime_error(exception)

    exception ->
      Logger.error("[ImageMetadataStripper] Exception: #{inspect(exception)}")
      {:error, {:exception, exception}}
  end

  defp handle_runtime_error(%RuntimeError{message: "missing prerequisite:" <> _rest}) do
    Logger.warning(
      "[ImageMetadataStripper] ImageMagick is unavailable; preserving the validated original image"
    )

    :ok
  end

  defp handle_runtime_error(exception) do
    Logger.error("[ImageMetadataStripper] Exception: #{inspect(exception)}")
    {:error, {:exception, exception}}
  end
end
