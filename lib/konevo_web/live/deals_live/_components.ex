defmodule KonevoWeb.DealsLive.Components do
  @moduledoc false
  use KonevoWeb, :html

  @doc """
  Renders a single deal card for the kanban board.
  """
  attr :deal, :map, required: true
  attr :id, :string, required: true
  attr :return_to, :string, required: true
  attr :rest, :global

  def deal_card(assigns) do
    ~H"""
    <div
      id={@id}
      data-id={@deal.id}
      class={[
        "drag-handle transform-gpu will-change-transform transition-transform duration-150",
        "active:cursor-grabbing"
      ]}
      {@rest}
    >
      <div class={[
        "group relative rounded-xl border border-base-content/10 bg-base-100 p-4 shadow-sm",
        "hover:border-base-content/20 hover:shadow-md transition-all duration-150"
      ]}>
        <%!-- Header: title + actions --%>
        <div class="flex items-start justify-between gap-2 mb-3">
          <h3 class="text-sm font-semibold text-base-content leading-snug line-clamp-2 flex-1 min-w-0">
            {@deal.title}
          </h3>

          <div class="flex items-center gap-1 shrink-0 opacity-100 transition-opacity md:opacity-0 md:group-hover:opacity-100">
            <.link
              patch={edit_path(@deal, @return_to)}
              class={[
                "flex size-8 items-center justify-center rounded-md border border-base-content/10 md:size-7",
                "bg-base-200/80 text-base-content/70 shadow-sm transition-all",
                "hover:border-primary/25 hover:bg-primary/10 hover:text-primary"
              ]}
              title={gettext("Edit deal")}
              aria-label={gettext("Edit deal")}
            >
              <.icon name="icon-[tabler--pencil]" class="size-3.5" />
            </.link>
            <button
              :if={is_nil(@deal.archived_at)}
              type="button"
              phx-click="archive_deal"
              phx-value-id={@deal.id}
              class={[
                "flex size-8 items-center justify-center rounded-md border border-base-content/10 md:size-7",
                "bg-base-200/80 text-base-content/70 shadow-sm transition-all",
                "hover:border-warning/25 hover:bg-warning/10 hover:text-warning"
              ]}
              title={gettext("Archive deal")}
              aria-label={gettext("Archive deal")}
            >
              <.icon name="icon-[tabler--archive]" class="size-3.5" />
            </button>
            <button
              :if={!is_nil(@deal.archived_at)}
              type="button"
              phx-click="restore_deal"
              phx-value-id={@deal.id}
              class={[
                "flex size-8 items-center justify-center rounded-md border border-base-content/10 md:size-7",
                "bg-base-200/80 text-base-content/70 shadow-sm transition-all",
                "hover:border-warning/25 hover:bg-warning/10 hover:text-warning"
              ]}
              title={gettext("Restore deal")}
              aria-label={gettext("Restore deal")}
            >
              <.icon name="icon-[tabler--archive-off]" class="size-3.5" />
            </button>
            <button
              type="button"
              phx-click="delete_deal"
              phx-value-id={@deal.id}
              data-confirm={gettext("Are you sure you want to delete this deal?")}
              class={[
                "flex size-8 items-center justify-center rounded-md border border-base-content/10 md:size-7",
                "bg-base-200/80 text-base-content/70 shadow-sm transition-all",
                "hover:border-red-600/25 hover:bg-red-600/10 hover:text-red-600"
              ]}
              title={gettext("Delete deal")}
              aria-label={gettext("Delete deal")}
            >
              <.icon name="icon-[tabler--trash]" class="size-3.5" />
            </button>
          </div>
        </div>
        <%!-- Contact --%>
        <div :if={@deal.contact} class="flex items-center gap-2 mb-3">
          <div class="flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/15 text-primary text-xs font-semibold">
            {contact_initial(@deal.contact)}
          </div>
          <span class="text-xs text-base-content/60 truncate">{contact_name(@deal.contact)}</span>
        </div>
        <%!-- Value + currency --%>
        <div class="flex items-center justify-between gap-2 mb-3">
          <div class="flex items-center gap-1">
            <span class="text-sm font-semibold text-base-content">
              {format_value(@deal.value, @deal.currency)}
            </span>
          </div>
          <%!-- Probability badge --%>
          <div
            :if={@deal.probability}
            class={[
              "inline-flex items-center gap-0.5 rounded-full px-2 py-0.5 text-xs font-medium",
              probability_class(@deal.probability)
            ]}
          >
            {@deal.probability}%
          </div>
        </div>
        <%!-- Footer: date + owner --%>
        <div class="flex items-center justify-between gap-2">
          <div
            :if={@deal.expected_close_date}
            class="flex items-center gap-1 text-xs text-base-content/50"
          >
            <span class="icon-[tabler--calendar] size-3.5 shrink-0" />
            <span>{format_date(@deal.expected_close_date)}</span>
          </div>
          <div :if={!@deal.expected_close_date} />
          <div :if={@deal.owner} class="flex items-center shrink-0">
            <div
              class="flex size-6 items-center justify-center rounded-full bg-base-200 text-base-content/60 text-xs font-semibold"
              title={@deal.owner.email}
            >
              {String.first(@deal.owner.email) |> String.upcase()}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp contact_initial(%{first_name: fn_}) when is_binary(fn_) and fn_ != "",
    do: String.first(fn_) |> String.upcase()

  defp contact_initial(_), do: "?"

  defp edit_path(deal, return_to) do
    case URI.parse(return_to).query do
      nil -> ~p"/deals/#{deal}/edit"
      query -> ~p"/deals/#{deal}/edit?#{URI.decode_query(query)}"
    end
  end

  defp contact_name(%{first_name: fn_, last_name: ln}) do
    [fn_, ln] |> Enum.filter(&(is_binary(&1) and &1 != "")) |> Enum.join(" ")
  end

  defp contact_name(_), do: ""

  defp format_value(nil, _currency), do: "-"

  defp format_value(value, currency) do
    num =
      value
      |> Decimal.round(0)
      |> Decimal.to_integer()
      |> abs()
      |> Integer.to_string()
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    sign = if Decimal.negative?(value), do: "-", else: ""
    "#{sign}#{num} #{currency_label(currency)}"
  end

  defp format_date(%Date{day: day, month: month, year: year}) do
    month_abbr =
      ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
      |> Enum.at(month - 1, "?")

    "#{day} #{month_abbr} #{year}"
  end

  defp probability_class(p) when p >= 75, do: "bg-success/15 text-success"
  defp probability_class(p) when p >= 40, do: "bg-warning/15 text-warning"
  defp probability_class(_), do: "bg-base-200 text-base-content/50"

  @doc """
  Renders a kanban stage column header.
  """
  attr :stage, :map, required: true
  attr :deals, :list, required: true
  attr :total, :integer, required: true

  def stage_column_header(assigns) do
    ~H"""
    <div class="relative px-4 py-3">
      <%!-- Subtle stage color tint background --%>
      <div
        class="absolute inset-0"
        style={"background-color: #{stage_color(@stage.color)}; opacity: 0.07;"}
      />
      <%!-- Colored accent line at the bottom of header --%>
      <div
        class="absolute bottom-0 left-0 right-0 h-0.5"
        style={"background-color: #{stage_color(@stage.color)}"}
      />
      <div class="relative flex items-center justify-between gap-2">
        <div class="flex items-center gap-2 min-w-0">
          <div
            class="size-2.5 rounded-full shrink-0"
            style={"background-color: #{stage_color(@stage.color)}"}
          />
          <h2 class="text-sm font-semibold text-base-content truncate">{@stage.name}</h2>
          <span class="badge badge-sm font-semibold" style={stage_count_style(@stage.color)}>
            {@total}
          </span>
        </div>

        <div class="flex items-center gap-1.5 shrink-0">
          <.link
            patch={~p"/deals/new?stage_id=#{@stage.id}"}
            class={[
              "flex size-7 items-center justify-center rounded-md border border-base-content/10",
              "shadow-sm transition-all hover:scale-105"
            ]}
            style={
              "color: #{stage_color(@stage.color)}; border-color: color-mix(in srgb, #{stage_color(@stage.color)} 24%, transparent); background-color: color-mix(in srgb, #{stage_color(@stage.color)} 10%, transparent);"
            }
            title={gettext("Add deal")}
            aria-label={gettext("Add deal")}
          >
            <.icon name="icon-[tabler--plus]" class="size-3.5" />
          </.link>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a collapsed kanban stage column (narrow vertical strip).
  """
  attr :stage, :map, required: true
  attr :deals, :list, required: true
  attr :total, :integer, required: true
  attr :on_expand, :any, required: true

  def stage_column_strip(assigns) do
    ~H"""
    <div
      phx-click={@on_expand}
      class="relative flex flex-1 flex-col items-center gap-3 py-4 px-1 overflow-hidden cursor-pointer group"
      role="button"
      tabindex="0"
      title={@stage.name}
    >
      <div
        class="absolute inset-0"
        style={"background-color: #{stage_color(@stage.color)}; opacity: 0.06;"}
      />
      <div
        class="absolute left-0 top-0 bottom-0 w-0.5"
        style={"background-color: #{stage_color(@stage.color)}"}
      />
      <.icon
        name="icon-[tabler--chevron-right]"
        class="relative z-10 size-4 shrink-0 text-base-content/40 transition-colors group-hover:text-base-content/80"
      />
      <span class="relative z-10 text-xs font-semibold text-base-content/60 transition-colors [writing-mode:vertical-rl] rotate-180 whitespace-nowrap group-hover:text-base-content/80">
        {@stage.name}
      </span>
      <span
        class="relative z-10 mt-auto badge badge-sm font-semibold"
        style={stage_count_style(@stage.color)}
      >
        {@total}
      </span>
    </div>
    """
  end

  defp stage_color(nil), do: "#9ca3af"
  defp stage_color("#6b7280"), do: "#4b5563"
  defp stage_color("#6B7280"), do: "#4b5563"
  defp stage_color(color), do: color

  defp stage_count_style(color) do
    color = stage_color(color)

    "color: #{color}; " <>
      "border-color: color-mix(in srgb, #{color} 28%, transparent); " <>
      "background-color: color-mix(in srgb, #{color} 14%, var(--color-base-100));"
  end

  defp currency_label(nil), do: ""
  defp currency_label(currency), do: String.upcase(currency)
end
