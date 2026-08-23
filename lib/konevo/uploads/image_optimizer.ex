defmodule Konevo.Uploads.ImageOptimizer do
  @moduledoc """
  Optimizes images using ImageMagick via the Mogrify library.

  Resizes to `max_dimension` (longest edge, no upscaling) and recompresses
  at `image_quality` for lossy formats (JPEG/WebP). Both axes are applied
  independently — dimension capping and quality reduction each deliver
  significant file-size savings and together maximise the effect.

  Requires ImageMagick to be installed on the host:
  - Alpine/Debian: `apk add imagemagick` / `apt-get install imagemagick`
  - macOS: `brew install imagemagick`
  """

  require Logger

  alias Konevo.Uploads.ImageMetadataStripper

  @doc """
  Optimize an image: resize and/or recompress, then optionally strip metadata.

  - `max_dimension`  — cap on the longest edge in pixels; `nil` skips resize
  - `quality`        — lossy compression 1-100; `nil` uses ImageMagick default
  - `strip_metadata` — when `true` (default), strips EXIF/IPTC/XMP after resize

  Returns `:ok` or `{:error, reason}`.
  """
  def optimize(file_path, max_dimension, quality, strip_metadata \\ true)
      when is_binary(file_path) and
             (is_integer(max_dimension) or is_nil(max_dimension)) and
             (is_integer(quality) or is_nil(quality)) and
             is_boolean(strip_metadata) do
    Mogrify.open(file_path)
    |> maybe_resize(max_dimension)
    |> maybe_set_quality(quality)
    |> Mogrify.save(in_place: true)

    if strip_metadata do
      case ImageMetadataStripper.strip_metadata(file_path) do
        :ok ->
          Logger.debug("[ImageOptimizer] Optimized + metadata stripped: #{file_path}")
          :ok

        {:error, reason} ->
          # Non-fatal: optimisation succeeded, stripping failed.
          Logger.warning("[ImageOptimizer] Optimized but strip failed: #{inspect(reason)}")
          :ok
      end
    else
      Logger.debug("[ImageOptimizer] Optimized: #{file_path}")
      :ok
    end
  rescue
    exception in RuntimeError ->
      handle_runtime_error(exception, file_path)

    exception ->
      Logger.error("[ImageOptimizer] Exception optimizing #{file_path}: #{inspect(exception)}")
      {:error, {:exception, exception}}
  end

  defp handle_runtime_error(
         %RuntimeError{message: "missing prerequisite:" <> _rest},
         file_path
       ) do
    Logger.warning(
      "[ImageOptimizer] ImageMagick is unavailable; preserving validated original: #{file_path}"
    )

    :ok
  end

  defp handle_runtime_error(exception, file_path) do
    Logger.error("[ImageOptimizer] Exception optimizing #{file_path}: #{inspect(exception)}")
    {:error, {:exception, exception}}
  end

  # "WxH>" means: resize to fit within WxH, preserve aspect ratio, never upscale.
  defp maybe_resize(pipe, nil), do: pipe

  defp maybe_resize(pipe, max_dimension)
       when is_integer(max_dimension) and max_dimension > 0 do
    Mogrify.resize(pipe, "#{max_dimension}x#{max_dimension}>")
  end

  defp maybe_set_quality(pipe, nil), do: pipe

  defp maybe_set_quality(pipe, quality)
       when is_integer(quality) and quality >= 1 and quality <= 100 do
    Mogrify.quality(pipe, "#{quality}")
  end
end
