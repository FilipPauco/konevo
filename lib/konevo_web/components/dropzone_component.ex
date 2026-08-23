defmodule KonevoWeb.Components.DropzoneComponent do
  @moduledoc """
  Reusable FlyonUI-style drag-and-drop upload zone.

  Parameterised by a single upload configuration. The parent LiveView owns
  `allow_upload`, `validate`,
  `cancel-upload`, and `save` — this component is pure UI.

  Usage:
    <.live_component
      module={KonevoWeb.Components.DropzoneComponent}
      id="doc-dropzone"
      upload={@uploads.document}
    />
  """

  use KonevoWeb, :live_component

  attr :id, :string, required: true
  attr :upload, :any, required: true
  attr :cancel_event, :string, default: "cancel-upload"
  attr :cancel_target, :any, default: nil
  attr :compact, :boolean, default: false
  attr :show_entries, :boolean, default: true

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :upload_error_messages, upload_error_messages(assigns.upload))

    ~H"""
    <div class="w-full">
      <%!-- Drop target area --%>
      <label
        id={"#{@id}-target"}
        for={@upload.ref}
        class={[
          "relative overflow-hidden border-2 border-dashed border-base-300 rounded-xl p-4",
          @compact && "p-3.5",
          "flex flex-col items-center justify-center gap-3",
          @compact && "gap-1.5",
          "bg-base-200/50 hover:bg-base-200 hover:border-primary/40",
          "focus-within:ring-2 focus-within:ring-primary/30 transition-all cursor-pointer"
        ]}
        phx-drop-target={@upload.ref}
      >
        <.icon
          name="icon-[tabler--cloud-upload]"
          class={
            if(@compact,
              do: "size-7 text-base-content/35",
              else: "size-12 text-base-content/40"
            )
          }
        />
        <div class="text-center">
          <p class={["font-medium text-base-content", @compact && "text-sm"]}>
            {gettext("Drag & drop files here")}
          </p>

          <p class={["text-base-content/60", if(@compact, do: "text-xs", else: "text-sm")]}>
            {gettext("or click to browse")}
          </p>
        </div>

        <span class={[
          "btn btn-primary pointer-events-none",
          if(@compact, do: "btn-xs", else: "btn-sm")
        ]}>
          {gettext("Browse files")}
        </span>
        <.live_file_input upload={@upload} class="sr-only" tabindex="-1" />

        <p class={[
          "text-center text-base-content/50",
          if(@compact, do: "text-[11px] leading-snug", else: "text-xs")
        ]}>
          Up to {@upload.max_entries} file(s) &middot;
          max {format_bytes(@upload.max_file_size)} each &middot; {format_accept(@upload.accept)}
        </p>
      </label>

      <%!-- Upload errors --%>
      <%= if @upload_error_messages != [] do %>
        <div
          id={"#{@id}-errors"}
          class="mt-3 rounded-lg border border-error/20 bg-error/10 p-3"
          role="alert"
        >
          <ul class="space-y-1 text-sm text-error">
            <%= for message <- @upload_error_messages do %>
              <li>{message}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <%!-- Entry list with progress and per-entry errors --%>
      <%= if @show_entries && @upload.entries != [] do %>
        <ul
          id={"#{@id}-entries"}
          class={[
            "mt-4 space-y-3",
            @compact && "mt-2 max-h-24 space-y-1.5 overflow-y-auto pr-1"
          ]}
        >
          <%= for entry <- @upload.entries, entry.valid? do %>
            <li class={[
              "flex items-center gap-3 rounded-lg bg-base-200",
              if(@compact, do: "gap-2 p-1.5", else: "p-3")
            ]}>
              <%!-- Thumbnail or file icon --%>
              <div class={[
                "flex shrink-0 items-center justify-center overflow-hidden rounded ring-1 ring-base-content/10 bg-base-300",
                if(@compact, do: "size-7", else: "size-12")
              ]}>
                <%= if image_entry?(entry.client_name) do %>
                  <.live_img_preview entry={entry} class="size-full object-cover" />
                <% else %>
                  <.icon
                    name="icon-[tabler--file]"
                    class={[
                      "text-base-content/50",
                      if(@compact, do: "size-4", else: "size-6")
                    ]}
                  />
                <% end %>
              </div>
              <%!-- Filename + progress --%>
              <div class="flex-1 min-w-0">
                <p class={[
                  "truncate font-medium text-base-content",
                  if(@compact, do: "text-xs", else: "text-sm")
                ]}>
                  {entry.client_name}
                </p>

                <div class={[
                  "flex items-center gap-2",
                  if(@compact, do: "mt-0.5", else: "mt-1")
                ]}>
                  <div class={[
                    "flex-1 bg-base-300 rounded-full overflow-hidden",
                    if(@compact, do: "h-1", else: "h-1.5")
                  ]}>
                    <div
                      class="h-full bg-primary transition-all duration-300"
                      style={"width: #{entry.progress}%"}
                    />
                  </div>

                  <span class={[
                    "w-8 text-right tabular-nums text-base-content/50",
                    if(@compact, do: "text-[11px]", else: "text-xs")
                  ]}>
                    {entry.progress}%
                  </span>
                </div>
              </div>
              <%!-- Cancel button --%>
              <button
                type="button"
                phx-click={@cancel_event}
                phx-value-ref={entry.ref}
                phx-target={@cancel_target}
                class={[
                  "flex-shrink-0 btn btn-ghost btn-xs btn-circle",
                  @compact && "size-6 min-h-6"
                ]}
                aria-label={"Remove #{entry.client_name}"}
              >
                <.icon
                  name="icon-[tabler--x]"
                  class={if(@compact, do: "size-3.5", else: "size-4")}
                />
              </button>
            </li>
          <% end %>
        </ul>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  # ---- Helpers ----

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes < 1_024 -> "#{bytes} B"
      bytes < 1_048_576 -> "#{Float.round(bytes / 1_024, 1)} KB"
      bytes < 1_073_741_824 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      true -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
    end
  end

  defp format_accept(accept) when is_binary(accept) do
    accept |> String.split(",") |> Enum.map_join(", ", &String.trim/1)
  end

  defp image_entry?(filename),
    do: String.match?(filename, ~r/\.(jpe?g|png|gif|webp)$/i)

  defp upload_error_messages(upload) do
    global_messages =
      Enum.map(upload_errors(upload), fn
        :too_many_files ->
          gettext("Choose no more than %{count} files at a time.", count: upload.max_entries)

        _error ->
          gettext("Those files could not be added. Please try again.")
      end)

    entry_messages =
      for entry <- upload.entries,
          error <- upload_errors(upload, entry),
          error != :not_accepted,
          do: entry_error_message(error, entry, upload)

    global_messages ++ entry_messages
  end

  defp entry_error_message(:too_large, entry, upload) do
    gettext(
      "“%{filename}” is too large. Choose a file smaller than %{size}.",
      filename: entry.client_name,
      size: format_bytes(upload.max_file_size)
    )
  end

  defp entry_error_message(_error, entry, _upload) do
    gettext("“%{filename}” could not be uploaded. Please try again.", filename: entry.client_name)
  end
end
