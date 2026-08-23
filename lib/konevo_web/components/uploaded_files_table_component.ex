defmodule KonevoWeb.Components.UploadedFilesTableComponent do
  @moduledoc """
  Paginated uploaded-files table.
  """

  use KonevoWeb, :html

  attr(:id, :string, required: true)
  attr(:rows, :any, required: true)
  attr(:page, :integer, required: true)
  attr(:total, :integer, required: true)
  attr(:per_page, :integer, required: true)
  attr(:class, :any, default: "mt-12")
  attr(:title, :string, default: nil)
  attr(:show_title, :boolean, default: true)
  attr(:show_footer, :boolean, default: true)
  attr(:update, :string, default: "stream")
  attr(:compact, :boolean, default: false)
  attr(:show_delete, :boolean, default: false)
  attr(:delete_event, :string, default: "delete_attachment")
  attr(:delete_target, :any, default: nil)

  def render(assigns) do
    assigns =
      assigns
      |> assign_pagination()
      |> assign(:title, assigns.title || gettext("Uploaded files"))

    ~H"""
    <section id={@id} class={@class}>
      <h2 :if={@show_title} class="mb-4 text-lg font-semibold text-base-content">{@title}</h2>

      <div class="overflow-hidden rounded-xl border border-base-content/20 bg-base-100">
        <div class="overflow-x-auto">
          <table class={["table w-full", @compact && "text-sm"]}>
            <thead>
              <tr
                class="divide-x divide-base-content/8"
                style="background-color: color-mix(in oklch, var(--color-primary) 10%, var(--color-base-100)); border-bottom: 1px solid color-mix(in oklch, var(--color-primary) 25%, transparent)"
              >
                <th class={header_cell_class(@compact)}>
                  <span class="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/60">
                    {gettext("Filename")}
                  </span>
                </th>
                <th class={header_cell_class(@compact)}>
                  <span class="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/60">
                    {gettext("Author")}
                  </span>
                </th>
                <th class={header_cell_class(@compact)}>
                  <span class="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/60">
                    {gettext("Size")}
                  </span>
                </th>
                <th class={header_cell_class(@compact)}>
                  <span class="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/60">
                    {gettext("Uploaded")}
                  </span>
                </th>
              </tr>
            </thead>
            <tbody id={"#{@id}-rows"} phx-update={@update} class="divide-y divide-base-content/8">
              <tr id={"#{@id}-empty"} class="hidden only:table-row">
                <td colspan="4" class={empty_cell_class(@compact)}>
                  <.icon
                    name="icon-[tabler--files-off]"
                    class="mx-auto mb-3 size-10 text-base-content/20"
                  />
                  <p class="text-sm font-medium text-base-content/50">
                    {gettext("No files uploaded yet.")}
                  </p>
                </td>
              </tr>
              <tr
                :for={{dom_id, row} <- @rows}
                id={dom_id}
                class="divide-x divide-base-content/8 transition-colors hover:bg-base-200/40"
              >
                <td class={filename_cell_class(@compact)}>
                  <div class={[
                    "flex items-center pr-8",
                    if(@compact, do: "gap-2", else: "gap-3")
                  ]}>
                    <span class={[
                      "flex shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary",
                      if(@compact, do: "size-7", else: "size-9")
                    ]}>
                      <.icon
                        name={file_icon(row.file.content_type)}
                        class={if(@compact, do: "size-4", else: "size-5")}
                      />
                    </span>
                    <.link
                      id={"#{dom_id}-filename"}
                      href={file_href(row.file)}
                      target={if(previewable_in_new_tab?(row.file.content_type), do: "_blank")}
                      rel={
                        if(previewable_in_new_tab?(row.file.content_type),
                          do: "noopener noreferrer"
                        )
                      }
                      data-lightbox={lightbox_type(row.file.content_type)}
                      data-lightbox-group={if(lightbox_type(row.file.content_type), do: @id)}
                      data-lightbox-title={
                        if(lightbox_type(row.file.content_type), do: row.file.original_filename)
                      }
                      download={
                        if(!previewable?(row.file.content_type), do: row.file.original_filename)
                      }
                      class={[
                        "truncate font-medium decoration-primary/60 underline-offset-2 transition-colors hover:text-primary hover:underline",
                        if(@compact, do: "text-xs", else: "text-sm")
                      ]}
                      title={row.file.original_filename}
                    >
                      {row.file.original_filename}
                    </.link>
                  </div>
                  <div
                    id={"#{dom_id}-actions"}
                    phx-hook="RowMenu"
                    class="absolute inset-y-0 right-3 flex items-center"
                  >
                    <button
                      type="button"
                      data-toggle
                      class={[
                        "flex items-center justify-center rounded-md text-base-content/40 transition-colors hover:bg-base-content/10 hover:text-base-content",
                        if(@compact, do: "size-6", else: "size-7")
                      ]}
                      aria-label={gettext("File actions")}
                    >
                      <.icon name="icon-[tabler--dots-vertical]" class="size-4" />
                    </button>
                    <ul
                      data-panel
                      class="row-menu-closed z-50 w-40 overflow-hidden rounded-lg border border-base-content/15 bg-base-100 p-1 shadow-xl shadow-base-content/10"
                      role="menu"
                    >
                      <li :if={previewable?(row.file.content_type)}>
                        <.link
                          id={"#{dom_id}-preview"}
                          href={~p"/uploads/#{row.file.context}/#{row.file.id}?preview=true"}
                          target={if(previewable_in_new_tab?(row.file.content_type), do: "_blank")}
                          rel={
                            if(previewable_in_new_tab?(row.file.content_type),
                              do: "noopener noreferrer"
                            )
                          }
                          data-lightbox={lightbox_type(row.file.content_type)}
                          data-lightbox-group={if(lightbox_type(row.file.content_type), do: @id)}
                          data-lightbox-title={
                            if(lightbox_type(row.file.content_type), do: row.file.original_filename)
                          }
                          class={menu_item_class(@compact)}
                        >
                          <.icon name="icon-[tabler--eye]" class="size-4" />
                          {gettext("Preview")}
                        </.link>
                      </li>
                      <li>
                        <.link
                          id={"#{dom_id}-download"}
                          href={~p"/uploads/#{row.file.context}/#{row.file.id}"}
                          download={row.file.original_filename}
                          class={menu_item_class(@compact)}
                        >
                          <.icon name="icon-[tabler--download]" class="size-4" />
                          {gettext("Download")}
                        </.link>
                      </li>
                      <li :if={@show_delete}>
                        <button
                          id={"#{dom_id}-delete"}
                          type="button"
                          phx-click={@delete_event}
                          phx-value-id={row.file.id}
                          phx-target={@delete_target}
                          data-confirm={gettext("Delete this attachment?")}
                          class={delete_menu_item_class(@compact)}
                        >
                          <.icon name="icon-[tabler--trash]" class="size-4" />
                          {gettext("Delete")}
                        </button>
                      </li>
                    </ul>
                  </div>
                </td>
                <td class={body_cell_class(@compact)}>
                  <div class="flex items-center gap-2.5">
                    <div class="avatar placeholder">
                      <div class={[
                        "flex items-center justify-center rounded-full bg-primary/10 text-primary",
                        if(@compact, do: "size-7", else: "size-8")
                      ]}>
                        <%= if row.avatar do %>
                          <img src={~p"/uploads/avatar/#{row.avatar.id}"} alt="" class="object-cover" />
                        <% else %>
                          <span
                            id={"#{dom_id}-author-initials"}
                            class="flex size-full items-center justify-center text-xs font-semibold"
                          >
                            {author_initials(row)}
                          </span>
                        <% end %>
                      </div>
                    </div>
                    <span class={[
                      "max-w-48 truncate text-base-content/70",
                      if(@compact, do: "text-xs", else: "text-sm")
                    ]}>
                      {author_name(row)}
                    </span>
                  </div>
                </td>
                <td class={meta_cell_class(@compact)}>
                  {format_megabytes(row.file.byte_size)}
                </td>
                <td class={meta_cell_class(@compact)}>
                  {Calendar.strftime(row.file.inserted_at, "%b %-d, %Y")}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div
        :if={@show_footer && @total > 0}
        class="mt-4 flex flex-wrap items-center justify-between gap-3"
      >
        <p class="text-sm text-base-content/50">
          <%= if @total == 0 do %>
            {gettext("No files found")}
          <% else %>
            {gettext("Showing %{from}–%{to} of %{total}", from: @from, to: @to, total: @total)}
          <% end %>
        </p>
        <nav :if={@total_pages > 1} aria-label={gettext("Uploaded files pagination")}>
          <ul class="flex items-center gap-0.5 rounded-xl border border-base-content/10 bg-base-100 p-1 shadow-sm">
            <li>
              <button
                id={"#{@id}-previous"}
                type="button"
                phx-click="uploaded_files_page"
                phx-value-page={@page - 1}
                disabled={@page == 1}
                class="flex h-8 w-8 items-center justify-center rounded-lg bg-base-content text-base-100 transition-all hover:opacity-80 disabled:pointer-events-none disabled:opacity-20"
                aria-label={gettext("Previous files page")}
              >
                <.icon name="icon-[tabler--chevron-left]" class="size-4" />
              </button>
            </li>
            <li :for={page <- @page_numbers}>
              <%= if page == :gap do %>
                <span class="flex h-8 w-8 items-center justify-center text-sm text-base-content/30 select-none">
                  …
                </span>
              <% else %>
                <button
                  id={"#{@id}-page-#{page}"}
                  type="button"
                  phx-click="uploaded_files_page"
                  phx-value-page={page}
                  aria-current={if(page == @page, do: "page")}
                  class={[
                    "flex h-8 w-8 items-center justify-center rounded-lg text-sm font-medium transition-all select-none",
                    if(page == @page,
                      do: "bg-primary text-primary-content shadow-sm ring-1 ring-primary/30",
                      else: "text-base-content/60 hover:bg-primary/10 hover:text-primary"
                    )
                  ]}
                >
                  {page}
                </button>
              <% end %>
            </li>
            <li>
              <button
                id={"#{@id}-next"}
                type="button"
                phx-click="uploaded_files_page"
                phx-value-page={@page + 1}
                disabled={@page >= @total_pages}
                class="flex h-8 w-8 items-center justify-center rounded-lg bg-base-content text-base-100 transition-all hover:opacity-80 disabled:pointer-events-none disabled:opacity-20"
                aria-label={gettext("Next files page")}
              >
                <.icon name="icon-[tabler--chevron-right]" class="size-4" />
              </button>
            </li>
          </ul>
        </nav>
      </div>

      <dialog
        id={"#{@id}-lightbox"}
        phx-hook="ImageLightbox"
        phx-update="ignore"
        data-lightbox-dialog
        data-lightbox-group={@id}
        class="m-auto h-dvh max-h-none w-screen max-w-none overflow-hidden bg-transparent p-0 text-base-content backdrop:bg-base-content/30 backdrop:backdrop-blur-[2px] sm:h-[min(88vh,56rem)] sm:w-[min(94vw,88rem)] sm:rounded-2xl"
        aria-labelledby={"#{@id}-lightbox-title"}
      >
        <div
          class="relative flex h-full w-full flex-col overflow-hidden bg-base-100 text-base-content shadow-2xl shadow-base-content/20 ring-1 ring-base-content/15 sm:rounded-2xl"
          data-lightbox-surface
        >
          <header
            class="relative z-20 flex h-12 shrink-0 items-center justify-between gap-4 border-b px-3 text-base-content shadow-sm sm:px-4"
            style="background-color: color-mix(in oklch, var(--color-primary) 10%, var(--color-base-100)); border-bottom-color: color-mix(in oklch, var(--color-primary) 25%, transparent)"
          >
            <div class="flex min-w-0 items-center gap-3">
              <p
                id={"#{@id}-lightbox-title"}
                data-lightbox-title
                class="truncate text-sm font-medium text-base-content/75"
              >
              </p>
              <span
                data-lightbox-counter
                class="shrink-0 rounded-full bg-primary/10 px-2 py-0.5 text-[0.7rem] font-medium text-primary ring-1 ring-primary/15"
              >
              </span>
            </div>
            <div class="flex shrink-0 items-center gap-1.5">
              <a
                data-lightbox-download
                class="flex size-9 items-center justify-center rounded-lg border border-base-content/15 bg-base-100 text-base-content/70 shadow-sm transition-all hover:border-primary/25 hover:bg-primary/10 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                aria-label={gettext("Download file")}
                title={gettext("Download file")}
              >
                <.icon name="icon-[tabler--download]" class="size-4.5" />
              </a>
              <button
                type="button"
                data-lightbox-zoom
                class="flex size-9 items-center justify-center rounded-lg border border-base-content/15 bg-base-100 text-base-content/70 shadow-sm transition-all hover:border-primary/25 hover:bg-primary/10 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                aria-label={gettext("Zoom image")}
                title={gettext("Zoom image")}
              >
                <.icon name="icon-[tabler--zoom-in]" class="size-4.5" />
              </button>
              <button
                type="button"
                data-lightbox-fullscreen
                data-expand-label={gettext("Enter fullscreen")}
                data-restore-label={gettext("Restore preview size")}
                class="hidden size-9 items-center justify-center rounded-lg border border-base-content/15 bg-base-100 text-base-content/70 shadow-sm transition-all hover:border-primary/25 hover:bg-primary/10 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary sm:flex"
                aria-label={gettext("Enter fullscreen")}
                aria-pressed="false"
                title={gettext("Enter fullscreen")}
              >
                <.icon
                  name="icon-[tabler--arrows-maximize]"
                  data-lightbox-expand-icon
                  class="size-4.5"
                />
                <.icon
                  name="icon-[tabler--arrows-minimize]"
                  data-lightbox-restore-icon
                  class="hidden size-4.5"
                />
              </button>
              <button
                type="button"
                data-lightbox-close
                class="ml-0.5 flex size-9 min-h-9 items-center justify-center rounded-lg border border-base-content/15 bg-base-content text-base-100 shadow-sm transition-all hover:bg-base-content/85 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                aria-label={gettext("Close file preview")}
                title={gettext("Close file preview")}
              >
                <.icon name="icon-[tabler--x]" class="size-5" />
              </button>
            </div>
          </header>

          <div
            data-lightbox-stage
            class="relative min-h-0 flex-1 touch-none overflow-hidden bg-base-200/70"
          >
            <div
              data-lightbox-loader
              class="pointer-events-none absolute inset-0 z-10 grid place-items-center opacity-0 transition-opacity"
              aria-hidden="true"
            >
              <.icon name="icon-[tabler--loader-2]" class="size-8 animate-spin text-primary" />
            </div>
            <img
              data-lightbox-image
              src=""
              alt=""
              draggable="false"
              class="h-full w-full cursor-zoom-in object-contain p-4 opacity-0 transition-[opacity,transform] duration-200 ease-out sm:p-8"
            />
            <iframe
              data-lightbox-frame
              src="about:blank"
              title={gettext("PDF preview")}
              class="hidden h-full w-full border-0 bg-base-100"
            >
            </iframe>
            <button
              type="button"
              data-lightbox-previous
              class="absolute top-1/2 left-3 flex size-11 -translate-y-1/2 items-center justify-center rounded-full bg-base-100/85 text-base-content/70 shadow-lg ring-1 ring-base-content/15 backdrop-blur transition hover:scale-105 hover:bg-primary/10 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary sm:left-6 sm:size-12"
              aria-label={gettext("Previous image")}
            >
              <.icon name="icon-[tabler--chevron-left]" class="size-6" />
            </button>
            <button
              type="button"
              data-lightbox-next
              class="absolute top-1/2 right-3 flex size-11 -translate-y-1/2 items-center justify-center rounded-full bg-base-100/85 text-base-content/70 shadow-lg ring-1 ring-base-content/15 backdrop-blur transition hover:scale-105 hover:bg-primary/10 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary sm:right-6 sm:size-12"
              aria-label={gettext("Next image")}
            >
              <.icon name="icon-[tabler--chevron-right]" class="size-6" />
            </button>
          </div>

          <div
            data-lightbox-thumbnails
            class="relative z-20 flex h-20 shrink-0 items-center justify-center gap-2 overflow-x-auto border-t border-base-content/10 bg-base-100/95 px-4"
            aria-label={gettext("Image thumbnails")}
          >
          </div>
        </div>
      </dialog>
    </section>
    """
  end

  defp assign_pagination(assigns) do
    total_pages = max(1, ceil(assigns.total / assigns.per_page))

    assigns
    |> assign(:total_pages, total_pages)
    |> assign(:page_numbers, page_display(assigns.page, total_pages))
    |> assign(
      :from,
      if(assigns.total == 0, do: 0, else: (assigns.page - 1) * assigns.per_page + 1)
    )
    |> assign(:to, min(assigns.page * assigns.per_page, assigns.total))
  end

  defp header_cell_class(true), do: "px-3 py-2 text-left text-xs"
  defp header_cell_class(false), do: "px-4 py-3 text-left"

  defp empty_cell_class(true), do: "px-3 py-8 text-center"
  defp empty_cell_class(false), do: "px-4 py-14 text-center"

  defp filename_cell_class(true), do: "relative max-w-72 px-3 py-2"
  defp filename_cell_class(false), do: "relative max-w-72 px-4 py-3"

  defp body_cell_class(true), do: "px-3 py-2"
  defp body_cell_class(false), do: "px-4 py-3"

  defp meta_cell_class(true), do: "whitespace-nowrap px-3 py-2 text-xs text-base-content/60"
  defp meta_cell_class(false), do: "whitespace-nowrap px-4 py-3 text-sm text-base-content/60"

  defp menu_item_class(true) do
    "flex items-center gap-2 rounded-md px-2.5 py-1.5 text-xs text-base-content/70 transition-colors hover:bg-primary/10 hover:text-primary"
  end

  defp menu_item_class(false) do
    "flex items-center gap-2 rounded-md px-3 py-2 text-sm text-base-content/70 transition-colors hover:bg-primary/10 hover:text-primary"
  end

  defp delete_menu_item_class(true) do
    "danger-action flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors"
  end

  defp delete_menu_item_class(false) do
    "danger-action flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-colors"
  end

  defp page_display(_current, total_pages) when total_pages <= 7,
    do: Enum.to_list(1..total_pages)

  defp page_display(current, total_pages) do
    pages =
      [1, total_pages, max(2, current - 1), current, min(total_pages - 1, current + 1)]
      |> Enum.filter(&(&1 >= 1 and &1 <= total_pages))
      |> Enum.sort()
      |> Enum.uniq()

    Enum.reduce(tl(pages), [hd(pages)], fn page, displayed ->
      if page - List.last(displayed) > 1,
        do: displayed ++ [:gap, page],
        else: displayed ++ [page]
    end)
  end

  defp format_megabytes(bytes),
    do: :erlang.float_to_binary(bytes / 1_048_576, decimals: 2) <> " MB"

  defp author_name(%{author: %{email: email}}), do: email
  defp author_name(_row), do: gettext("Unknown user")

  defp author_initials(row) do
    row
    |> author_name()
    |> String.slice(0, 2)
    |> String.upcase()
  end

  defp previewable?("application/pdf"), do: true
  defp previewable?("image/" <> _subtype), do: true
  defp previewable?("audio/" <> _subtype), do: true
  defp previewable?("video/" <> _subtype), do: true
  defp previewable?(_content_type), do: false

  defp previewable_in_new_tab?(content_type),
    do: previewable?(content_type) and is_nil(lightbox_type(content_type))

  defp lightbox_type("application/pdf"), do: "pdf"
  defp lightbox_type("image/" <> _subtype), do: "image"
  defp lightbox_type(_content_type), do: nil

  defp file_href(file) do
    if previewable?(file.content_type) do
      ~p"/uploads/#{file.context}/#{file.id}?preview=true"
    else
      ~p"/uploads/#{file.context}/#{file.id}"
    end
  end

  defp file_icon("image/" <> _), do: "icon-[tabler--photo]"
  defp file_icon("application/pdf"), do: "icon-[tabler--file-type-pdf]"
  defp file_icon(_content_type), do: "icon-[tabler--file-description]"
end
