defmodule KonevoWeb.DocumentUploadLive do
  @moduledoc """
  LiveView for document uploads (:document context).

  Demonstrates the full, correct wiring pattern for Phoenix LiveView file uploads
  with local storage via UploadProcessor. Use as a template for other contexts.
  """

  use KonevoWeb, :live_view

  require Logger

  alias Konevo.Uploads.{UploadConfig, UploadProcessor}

  @upload_context :document

  @impl true
  def mount(_params, _session, socket) do
    config = UploadConfig.get!(@upload_context)

    socket =
      socket
      |> assign(:upload_context, @upload_context)
      |> assign(:documents, [])
      |> allow_upload(@upload_context,
        accept: config.allowed_extensions,
        auto_upload: true,
        max_entries: config.max_entries,
        max_file_size: config.max_file_size
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl px-4 py-10">
        <h1 class="text-2xl font-bold text-base-content mb-1">Upload Documents</h1>

        <p class="text-base-content/60 mb-6 text-sm">
          PDF, Word, PowerPoint, Excel, CSV &mdash; up to 25 MB each, 5 files at once.
        </p>

        <form id="document-upload-form" phx-submit="save" phx-change="validate">
          <.live_component
            module={KonevoWeb.Components.DropzoneComponent}
            id="document-dropzone"
            upload={@uploads[@upload_context]}
          />
          <div class="mt-6 flex justify-end">
            <.button
              type="submit"
              phx-disable-with="Uploading..."
              disabled={@uploads[@upload_context].entries == []}
            >
              Upload
            </.button>
          </div>
        </form>

        <div class="mt-12 border-t border-base-200 pt-10">
          <h2 class="text-lg font-semibold text-base-content">Profile picture uploader</h2>
          <p class="mb-5 mt-1 text-sm text-base-content/60">
            Local preview demo using the FlyonUI single-image upload pattern.
          </p>
          <KonevoWeb.Components.ProfilePictureUploadDemoComponent.render id="profile-picture-demo" />
        </div>
        <%!-- Uploaded files list --%>
        <%= if @documents != [] do %>
          <div class="mt-8">
            <h2 class="text-base font-semibold text-base-content mb-3">Uploaded</h2>

            <ul class="space-y-2">
              <%= for file <- @documents do %>
                <li class="flex items-center gap-3 p-3 bg-base-200 rounded-lg">
                  <.icon
                    name="icon-[tabler--file-description]"
                    class="w-5 h-5 text-base-content/50 flex-shrink-0"
                  />
                  <span class="text-sm text-base-content flex-1 truncate">
                    {file.original_filename}
                  </span>
                  <span class="text-xs text-base-content/40">{format_bytes(file.byte_size)}</span>
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", _params, socket) do
    rejected_entries =
      Enum.filter(socket.assigns.uploads.document.entries, fn entry ->
        :not_accepted in upload_errors(socket.assigns.uploads.document, entry)
      end)

    socket =
      Enum.reduce(rejected_entries, socket, fn entry, socket ->
        cancel_upload(socket, @upload_context, entry.ref)
      end)

    socket =
      if rejected_entries == [] do
        socket
      else
        put_flash(socket, :error, gettext("Unsupported file type"))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, @upload_context, ref)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    # Resolve tenant and owner exclusively from authenticated socket assigns —
    # never from event params.
    tenant_id = to_string(socket.assigns.current_scope.org.id)
    owner_id = to_string(socket.assigns.current_scope.user.id)

    results =
      consume_uploaded_entries(socket, @upload_context, fn %{path: temp_path}, entry ->
        case UploadProcessor.process(
               temp_path,
               @upload_context,
               tenant_id,
               owner_id,
               "user",
               entry.client_name
             ) do
          {:ok, record} ->
            {:ok, {:ok, record}}

          {:error, reason} ->
            Logger.warning(
              "[DocumentUploadLive] Upload failed for #{entry.client_name}: #{inspect(reason)}"
            )

            {:ok, {:error, format_error(reason)}}
        end
      end)

    {successes, failures} =
      Enum.split_with(results, &match?({:ok, _}, &1))

    uploaded_records = Enum.map(successes, fn {:ok, record} -> record end)

    socket =
      socket
      |> update(:documents, &(uploaded_records ++ &1))
      |> flash_result(length(successes), failures)

    {:noreply, socket}
  end

  # ---- Helpers ----

  defp flash_result(socket, 0, failures) do
    put_flash(
      socket,
      :error,
      "All uploads failed: #{Enum.map_join(failures, "; ", fn {:error, msg} -> msg end)}"
    )
  end

  defp flash_result(socket, count, []) do
    put_flash(socket, :success, "#{count} file(s) uploaded successfully")
  end

  defp flash_result(socket, count, failures) do
    put_flash(
      socket,
      :warning,
      "#{count} file(s) uploaded; #{length(failures)} failed: #{Enum.map_join(failures, "; ", fn {:error, msg} -> msg end)}"
    )
  end

  defp format_error({:extension_not_allowed, ext}), do: "#{ext} is not allowed"
  defp format_error({:file_too_large, _, max}), do: "File exceeds #{format_bytes(max)}"
  defp format_error({:content_type_not_allowed, _}), do: "File content is not allowed"
  defp format_error({:malware_detected, _}), do: "File flagged as unsafe"
  defp format_error({:database_error, _}), do: "Could not save file record"
  defp format_error(_), do: "Upload failed"

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes < 1_024 -> "#{bytes} B"
      bytes < 1_048_576 -> "#{Float.round(bytes / 1_024, 1)} KB"
      bytes < 1_073_741_824 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      true -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
    end
  end
end
