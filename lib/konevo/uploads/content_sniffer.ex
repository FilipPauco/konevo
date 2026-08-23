defmodule Konevo.Uploads.ContentSniffer do
  @moduledoc """
  Validates file content by checking magic bytes / file signatures.

  This prevents spoofed-extension attacks where a malicious file is renamed
  to have a trusted extension.
  """

  @doc """
  Sniff the content type of a file by reading its magic bytes.

  Returns {:ok, type_family, content_type} or {:error, reason}.
  """
  def sniff(file_path) when is_binary(file_path) do
    with {:ok, bytes} <- read_magic_bytes(file_path),
         {:ok, type_family, content_type} <- identify_type(bytes) do
      {:ok, type_family, content_type}
    else
      error -> error
    end
  end

  @doc """
  Validate that a file's actual content matches its expected type family.

  Returns :ok or {:error, reason}.
  """
  def validate_content(file_path, expected_families) when is_list(expected_families) do
    case sniff(file_path) do
      {:ok, type_family, _content_type} ->
        if type_family in expected_families do
          :ok
        else
          {:error, {:content_type_mismatch, type_family}}
        end

      error ->
        error
    end
  end

  # Read at most 64 KB — enough for all magic-byte patterns and ZIP local-file
  # headers (Office paths appear in the first few entries, well within 64 KB).
  # This avoids loading multi-hundred-MB video files into memory.
  defp read_magic_bytes(file_path) do
    case :file.open(file_path, [:read, :binary]) do
      {:ok, fd} ->
        result = :file.read(fd, 65_536)
        :file.close(fd)

        case result do
          {:ok, data} -> {:ok, data}
          :eof -> {:ok, <<>>}
          {:error, reason} -> {:error, {:read_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:read_failed, reason}}
    end
  end

  defp identify_type(bytes) when is_binary(bytes) do
    with :unknown <- identify_image_type(bytes),
         :unknown <- identify_media_type(bytes) do
      identify_document_type(bytes)
    end
  end

  defp identify_image_type(bytes) do
    cond do
      match_jpeg?(bytes) -> {:ok, :jpeg, "image/jpeg"}
      match_png?(bytes) -> {:ok, :png, "image/png"}
      match_gif?(bytes) -> {:ok, :gif, "image/gif"}
      match_webp?(bytes) -> {:ok, :webp, "image/webp"}
      true -> :unknown
    end
  end

  defp identify_media_type(bytes) do
    cond do
      match_webm?(bytes) -> {:ok, :webm, "video/webm"}
      match_mp3?(bytes) -> {:ok, :mp3, "audio/mpeg"}
      match_wav?(bytes) -> {:ok, :wav, "audio/wav"}
      match_ogg?(bytes) -> {:ok, :ogg, "audio/ogg"}
      # MP4 and MOV both use an ftyp box; distinguish by the major brand.
      match_ftyp_video?(bytes) -> identify_ftyp_video(bytes)
      true -> :unknown
    end
  end

  defp identify_document_type(bytes) do
    cond do
      match_pdf?(bytes) -> {:ok, :pdf, "application/pdf"}
      match_office_zip?(bytes) -> identify_office_doc(bytes)
      match_ole2?(bytes) -> {:ok, :doc, "application/msword"}
      # CSV has no magic bytes — accept only valid UTF-8 text with no null bytes.
      match_csv?(bytes) -> {:ok, :csv, "text/csv"}
      true -> {:error, {:unknown_type}}
    end
  end

  # JPEG: FFD8FFxx
  defp match_jpeg?(<<0xFF, 0xD8, 0xFF, _::binary>>), do: true
  defp match_jpeg?(_), do: false

  # PNG: 89504E47
  defp match_png?(<<0x89, 0x50, 0x4E, 0x47, _::binary>>), do: true
  defp match_png?(_), do: false

  # GIF: 474946 ("GIF")
  defp match_gif?(<<"GIF8", _::binary>>), do: true
  defp match_gif?(_), do: false

  # WEBP: RIFF....WEBP
  defp match_webp?(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: true
  defp match_webp?(_), do: false

  # PDF: %PDF-
  defp match_pdf?(<<"%PDF-", _::binary>>), do: true
  defp match_pdf?(_), do: false

  # WEBM: EBML header
  defp match_webm?(<<0x1A, 0x45, 0xDF, 0xA3, _::binary>>), do: true
  defp match_webm?(_), do: false

  # MP4: ftyp box is at offset 4; major brand distinguishes it from MOV.
  # Any brand other than "qt  " (QuickTime) is treated as MP4.
  defp match_ftyp_video?(<<_::binary-size(4), "ftyp", _::binary>>), do: true
  defp match_ftyp_video?(_), do: false

  defp identify_ftyp_video(<<_::binary-size(8), "qt  ", _::binary>>),
    do: {:ok, :mov, "video/quicktime"}

  defp identify_ftyp_video(_), do: {:ok, :mp4, "video/mp4"}

  # MP3: ID3 tag or MPEG frame sync
  defp match_mp3?(<<"ID3", _::binary>>), do: true
  defp match_mp3?(<<0xFF, 0xFB, _::binary>>), do: true
  defp match_mp3?(<<0xFF, 0xFA, _::binary>>), do: true
  defp match_mp3?(_), do: false

  # WAV: RIFF....WAVE
  defp match_wav?(<<"RIFF", _::binary-size(4), "WAVE", _::binary>>), do: true
  defp match_wav?(_), do: false

  # OGG: OggS
  defp match_ogg?(<<"OggS", _::binary>>), do: true
  defp match_ogg?(_), do: false

  # Office ZIP: All Office 2007+ formats are ZIP-based
  defp match_office_zip?(<<"PK", 0x03, 0x04, _::binary>>), do: true
  defp match_office_zip?(_), do: false

  # OLE2 (old Office): signature
  defp match_ole2?(<<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, _::binary>>), do: true
  defp match_ole2?(_), do: false

  defp identify_office_doc(bytes) do
    case identify_zip_contents(bytes) do
      {:ok, format} -> {:ok, format, mime_for_office_format(format)}
      error -> error
    end
  end

  # CSV: no magic bytes — must be valid UTF-8/ASCII text with no null bytes.
  defp match_csv?(bytes), do: String.valid?(bytes) and not String.contains?(bytes, <<0>>)

  defp identify_zip_contents(bytes) do
    # Try to extract central directory and find specific paths
    cond do
      contains_zip_path?(bytes, "word/document.xml") -> {:ok, :docx}
      contains_zip_path?(bytes, "word/") -> {:ok, :docx}
      contains_zip_path?(bytes, "xl/workbook.xml") -> {:ok, :xlsx}
      contains_zip_path?(bytes, "xl/") -> {:ok, :xlsx}
      contains_zip_path?(bytes, "ppt/presentation.xml") -> {:ok, :pptx}
      contains_zip_path?(bytes, "ppt/") -> {:ok, :pptx}
      true -> {:error, {:unknown_office_format}}
    end
  end

  # Simple heuristic: search for the path string in the ZIP
  defp contains_zip_path?(bytes, path) do
    String.contains?(bytes, path)
  end

  defp mime_for_office_format(:docx) do
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  end

  defp mime_for_office_format(:xlsx) do
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  defp mime_for_office_format(:pptx) do
    "application/vnd.openxmlformats-officedocument.presentationml.presentation"
  end
end
