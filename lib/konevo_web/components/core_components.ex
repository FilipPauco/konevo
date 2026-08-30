defmodule KonevoWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with FlyonUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [FlyonUI](https://flyonui.com/docs/getting-started/introduction/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Iconify](https://iconify.design) - use the `<.icon name="icon-[tabler--x]" />` component with any Iconify icon name.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: KonevoWeb.Gettext
  import LiveSelect

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @doc """
  Renders a modal overlay.

  ## Examples

      <.modal id="confirm-modal" show on_cancel={JS.patch(~p"/items")}>
        Are you sure?
      </.modal>
  """
  attr(:id, :string, required: true)
  attr(:show, :boolean, default: false)
  attr(:on_cancel, JS, default: %JS{})
  slot(:inner_block, required: true)

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      class="relative z-50 hidden"
    >
      <%!-- Backdrop --%>
      <div
        id={"#{@id}-backdrop"}
        class="fixed inset-0 bg-black/50 backdrop-blur-sm"
        aria-hidden="true"
        phx-click={@on_cancel}
      />
      <%!-- Panel --%>
      <div
        class="fixed inset-0 overflow-y-auto"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
      >
        <div class="flex min-h-full items-center justify-center p-4">
          <div
            id={"#{@id}-content"}
            class="relative w-full max-w-xl rounded-2xl bg-base-100 p-6 shadow-xl"
          >
            <button
              type="button"
              class="btn btn-sm btn-square btn-ghost absolute right-3 top-3"
              phx-click={@on_cancel}
              aria-label={gettext("Close")}
            >
              <.icon name="icon-[tabler--x]" class="size-4" />
            </button>
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc false
  def show_modal(id) do
    %JS{}
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-backdrop",
      transition: {"ease-out duration-200", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-content",
      transition:
        {"ease-out duration-200", "opacity-0 translate-y-2 scale-95",
         "opacity-100 translate-y-0 scale-100"}
    )
    |> JS.focus_first(to: "##{id}-content")
  end

  @doc false
  def hide_modal(id) do
    %JS{}
    |> JS.hide(
      to: "##{id}-backdrop",
      transition: {"ease-in duration-150", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-content",
      transition:
        {"ease-in duration-150", "opacity-100 translate-y-0 scale-100",
         "opacity-0 translate-y-2 scale-95"}
    )
    |> JS.hide(to: "##{id}", transition: {"block", "block", "block"})
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr(:id, :string, doc: "the optional id of flash container")
  attr(:flash, :map, default: %{}, doc: "the map of flash messages to display")
  attr(:title, :string, default: nil)

  attr(:kind, :atom,
    values: [:info, :success, :warning, :error],
    doc: "used for styling and flash lookup"
  )

  attr(:rest, :global, doc: "the arbitrary HTML attributes to add to the flash container")

  slot(:inner_block, doc: "the optional inner block that renders the flash message")

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-hook="FlashToast"
      role="alert"
      class="fixed top-4 right-4 z-50 notyf-toast"
      {@rest}
    >
      <div class={[
        "flex items-stretch overflow-hidden rounded-lg border border-black/15 shadow-2xl w-80 sm:w-96 max-w-sm text-white select-none",
        @kind == :success && "bg-[#22c55e]",
        @kind == :info && "bg-[#3b82f6]",
        @kind == :warning && "bg-[#f59e0b]",
        @kind == :error && "bg-[#ef4444]"
      ]}>
        <%!-- Main content --%>
        <div class="flex items-center gap-3 flex-1 px-4 py-2">
          <%!-- Icon — big, white circle bg --%>
          <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-white/25 ring-4 ring-white/20">
            <span
              :if={@kind == :success}
              class="icon-[tabler--circle-check] size-5 text-white"
            />
            <span :if={@kind == :info} class="icon-[tabler--info-circle] size-5 text-white" />
            <span
              :if={@kind == :warning}
              class="icon-[tabler--alert-triangle] size-5 text-white"
            />
            <span :if={@kind == :error} class="icon-[tabler--alert-circle] size-5 text-white" />
          </div>
          <%!-- Message --%>
          <div class="flex-1 min-w-0">
            <p :if={@title} class="font-semibold text-sm">{@title}</p>
            <p class="text-sm font-medium leading-snug">{flash_message(msg)}</p>
          </div>
        </div>
        <%!-- Dismiss panel --%>
        <button
          type="button"
          phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
          class="flex items-center justify-center border-l !rounded-l-none border-white/10 bg-black/25 px-3 transition-colors hover:bg-black/35 cursor-pointer"
          aria-label={gettext("close")}
        >
          <span class="icon-[tabler--x] size-[1.1rem] text-white" />
        </button>
      </div>
    </div>
    """
  end

  defp flash_message(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.replace(~r/[.!?]+\s*$/, "")
  end

  defp flash_message(message), do: message

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr(:rest, :global, include: ~w(href navigate patch method download name value disabled type))
  attr(:class, :any)
  attr(:variant, :string, values: ~w(primary outline ghost))
  slot(:inner_block, required: true)

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" => "btn-primary",
      "outline" => "btn-outline",
      "ghost" => "btn-ghost",
      nil => "btn-primary"
    }

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>{render_slot(@inner_block)}</.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>{render_slot(@inner_block)}</button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:value, :any)

  attr(:type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               range search select tel text textarea time url week hidden)
  )

  attr(:field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"
  )

  attr(:errors, :list, default: [])
  attr(:checked, :boolean, doc: "the checked flag for checkbox inputs")
  attr(:prompt, :string, default: nil, doc: "the prompt for select inputs")
  attr(:options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2")
  attr(:multiple, :boolean, default: false, doc: "the multiple flag for select inputs")
  attr(:required, :boolean, default: false, doc: "marks the input as required")
  attr(:class, :any, default: nil, doc: "the input class to use over defaults")
  attr(:error_class, :any, default: nil, doc: "the input error class to use over defaults")
  attr(:suffix, :string, default: nil, doc: "the suffix to display for range values")

  attr(:rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly rows size step)
  )

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    required =
      assigns[:required] ||
        case field.form.source do
          %Ecto.Changeset{required: required_fields} -> field.field in required_fields
          _ -> false
        end

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign(:required, required)
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}<span :if={@required} class="text-error ml-0.5">*</span>
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id} class="flex flex-col gap-2">
        <span :if={@label} class="label">
          {@label}<span :if={@required} class="text-error ml-0.5">*</span>
        </span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "is-invalid")]}
          multiple={@multiple}
          required={@required}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id} class="flex flex-col gap-2">
        <span :if={@label} class="label">
          {@label}<span :if={@required} class="text-error ml-0.5">*</span>
        </span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "is-invalid")
          ]}
          required={@required}
          data-autoresize
          phx-hook="AutoResize"
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "range"} = assigns) do
    min_value = range_bound(assigns.rest, :min, 0)
    max_value = range_bound(assigns.rest, :max, 100)

    assigns =
      assigns
      |> assign(:min_value, min_value)
      |> assign(:max_value, max_value)
      |> assign(:range_value, range_value(assigns.value, min_value, max_value))

    ~H"""
    <div
      id={"#{@id}-range-field"}
      class="fieldset mb-2"
      phx-hook="RangeInput"
      data-suffix={@suffix}
    >
      <label for={@id} class="flex flex-col gap-2">
        <span :if={@label} class="label flex items-center justify-between gap-3">
          <span>
            {@label}<span :if={@required} class="text-error ml-0.5">*</span>
          </span>
          <span
            data-range-value
            class="inline-flex shrink-0 items-center gap-1 rounded-lg border border-primary/20 bg-primary/10 px-2 py-1 text-xs font-semibold text-primary transition-colors"
          >
            {range_display_value(@range_value, @suffix)}
          </span>
        </span>
        <div class={[
          "rounded-lg border border-base-content/10 bg-base-100 px-3 py-3 shadow-sm transition-colors",
          @errors != [] && (@error_class || "border-error/40")
        ]}>
          <input
            type="range"
            name={@name}
            id={@id}
            value={@range_value}
            class={[@class || "range range-primary w-full", @errors != [] && "is-invalid"]}
            required={@required}
            aria-label={@label}
            data-range-fill
            phx-debounce="blur"
            {@rest}
          />
          <div class="mt-2 flex items-center justify-between text-xs font-medium text-base-content/50">
            <span>{range_display_value(@min_value, @suffix)}</span>
            <span>{range_display_value(@max_value, @suffix)}</span>
          </div>
        </div>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id} class="flex flex-col gap-2">
        <span :if={@label} class="label">
          {@label}<span :if={@required} class="text-error ml-0.5">*</span>
        </span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "is-invalid")
          ]}
          required={@required}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp range_bound(rest, key, default) do
    Map.get(rest, key) || Map.get(rest, to_string(key)) || default
  end

  defp range_value(nil, min, max) do
    with {:ok, min_number} <- range_number(min),
         {:ok, max_number} <- range_number(max) do
      ((min_number + max_number) / 2)
      |> round()
      |> Integer.to_string()
    else
      :error -> min
    end
  end

  defp range_value("", min, max), do: range_value(nil, min, max)
  defp range_value(value, _min, _max), do: Form.normalize_value("range", value)

  defp range_number(value) when is_integer(value), do: {:ok, value}
  defp range_number(value) when is_float(value), do: {:ok, value}

  defp range_number(value) do
    case Float.parse(to_string(value)) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp range_display_value(value, nil), do: value
  defp range_display_value(value, suffix), do: "#{value}#{suffix}"

  @doc """
  Renders an Active/Archived/All filter dropdown.
  """
  attr(:id, :string, required: true)
  attr(:selected, :atom, required: true)
  attr(:options, :list, required: true)
  attr(:event, :string, default: "set_archive_filter")
  attr(:label, :string, default: nil)

  def archive_filter_dropdown(assigns) do
    selected_value = Atom.to_string(assigns.selected)

    {selected_label, _value, selected_icon} =
      Enum.find(assigns.options, fn {_label, value, _icon} -> value == selected_value end) ||
        List.first(assigns.options) ||
        {gettext("Active"), "active", "icon-[tabler--circle-check]"}

    assigns =
      assigns
      |> assign(:selected_value, selected_value)
      |> assign(:selected_label, selected_label)
      |> assign(:selected_icon, selected_icon)
      |> assign(:filter_active?, selected_value != "active")

    ~H"""
    <div id={@id} class="relative" phx-hook="FilterPanel">
      <button
        type="button"
        data-toggle
        aria-label={@label || gettext("Archive filter")}
        class={[
          "btn btn-sm gap-1.5 border transition-all",
          if(@filter_active?,
            do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
            else: "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
          )
        ]}
      >
        <.icon name={@selected_icon} class="size-3.5" />
        {@selected_label}
        <.icon name="icon-[tabler--chevron-down]" class="size-3.5 opacity-50" />
      </button>

      <div
        data-panel
        class="row-menu-closed z-30 min-w-44 overflow-hidden rounded-xl border border-base-content/20 bg-base-100 p-1 shadow-xl"
      >
        <button
          :for={{label, value, icon} <- @options}
          type="button"
          phx-click={@event}
          phx-value-filter={value}
          data-close-panel
          class={[
            "flex w-full items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
            cond do
              value == @selected_value and value != "active" ->
                "bg-primary/10 text-primary"

              value == @selected_value ->
                "bg-base-200 text-base-content"

              true ->
                "text-base-content/70 hover:bg-base-200 hover:text-base-content"
            end
          ]}
        >
          <.icon name={icon} class="size-3.5 shrink-0" />
          <span class="min-w-0 flex-1 text-left">{label}</span>
          <.icon
            :if={value == @selected_value}
            name="icon-[tabler--check]"
            class="size-3.5 shrink-0"
          />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a date range picker

  ## Examples

      <.date_range_picker id="created-filter" created_from={@created_from} created_to={@created_to} />
  """
  attr(:id, :string, required: true)
  attr(:created_from, :string, default: "")
  attr(:created_to, :string, default: "")
  attr(:empty_label, :string, default: nil)

  def date_range_picker(assigns) do
    label =
      cond do
        assigns.created_from != "" and assigns.created_to != "" ->
          "#{assigns.created_from} – #{assigns.created_to}"

        assigns.created_from != "" ->
          gettext("From %{date}", date: assigns.created_from)

        assigns.created_to != "" ->
          gettext("Until %{date}", date: assigns.created_to)

        true ->
          assigns.empty_label || gettext("Created date")
      end

    active = assigns.created_from != "" or assigns.created_to != ""
    assigns = assign(assigns, label: label, active: active)

    ~H"""
    <div
      id={@id}
      class="relative"
      phx-hook="DateRangePicker"
      data-from={@created_from}
      data-to={@created_to}
    >
      <%!-- Trigger button (server-rendered label updates on push_patch) --%>
      <button
        type="button"
        data-trigger
        class={[
          "btn btn-sm gap-1.5 border select-none transition-all",
          if(@active,
            do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
            else: "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
          )
        ]}
      >
        <span class="icon-[tabler--calendar] size-3.5" />
        {@label}
        <span
          :if={@active}
          class="flex size-4 items-center justify-center rounded-full bg-primary text-[10px] font-bold text-primary-content"
        >
          1
        </span>
        <span class="icon-[tabler--chevron-down] size-3.5 opacity-50" />
      </button>

      <%!-- Dropdown panel --%>
      <div
        data-panel
        class="hidden absolute left-0 top-full z-30 mt-1 flex overflow-hidden rounded-xl border border-base-content/20 bg-base-100 shadow-xl"
      >
        <%!-- Preset sidebar --%>
        <div class="border-r border-base-content/10 p-2 flex flex-col gap-0.5 min-w-32">
          <button
            type="button"
            data-preset="today"
            class="w-full rounded-lg px-3 py-1.5 text-left text-sm text-base-content hover:bg-base-200 transition-colors whitespace-nowrap"
          >
            {gettext("Today")}
          </button>
          <button
            type="button"
            data-preset="this_week"
            class="w-full rounded-lg px-3 py-1.5 text-left text-sm text-base-content hover:bg-base-200 transition-colors whitespace-nowrap"
          >
            {gettext("This week")}
          </button>
          <button
            type="button"
            data-preset="last_week"
            class="w-full rounded-lg px-3 py-1.5 text-left text-sm text-base-content hover:bg-base-200 transition-colors whitespace-nowrap"
          >
            {gettext("Last week")}
          </button>
          <button
            type="button"
            data-preset="this_month"
            class="w-full rounded-lg px-3 py-1.5 text-left text-sm text-base-content hover:bg-base-200 transition-colors whitespace-nowrap"
          >
            {gettext("This month")}
          </button>
          <button
            type="button"
            data-preset="last_month"
            class="w-full rounded-lg px-3 py-1.5 text-left text-sm text-base-content hover:bg-base-200 transition-colors whitespace-nowrap"
          >
            {gettext("Last month")}
          </button>
          <button
            type="button"
            data-preset="this_year"
            class="w-full rounded-lg px-3 py-1.5 text-left text-sm text-base-content hover:bg-base-200 transition-colors whitespace-nowrap"
          >
            {gettext("This year")}
          </button>
          <button
            type="button"
            data-preset="last_year"
            class="w-full rounded-lg px-3 py-1.5 text-left text-sm text-base-content hover:bg-base-200 transition-colors whitespace-nowrap"
          >
            {gettext("Last year")}
          </button>
          <div class="my-1 border-t border-base-content/10" />
          <button
            type="button"
            data-preset="all_time"
            class="w-full rounded-lg px-3 py-1.5 text-left text-sm text-base-content/60 hover:bg-base-200 transition-colors whitespace-nowrap"
          >
            {gettext("All time")}
          </button>
        </div>

        <%!-- Inline flatpickr calendar — phx-update="ignore" protects it from LiveView patches --%>
        <div id={"#{@id}-cal-wrap"} phx-update="ignore">
          <div data-calendar id={"#{@id}-cal"} class="p-2"></div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a flatpickr date/date-range input integrated with LiveView forms.

  ## Examples

      <.date_picker field={@form[:start_date]} label="Start date" />
      <.date_picker field={@form[:date_range]} label="Date range" mode="range" />
      <.date_picker field={@form[:due_at]} label="Due" mode="single" date_format="Y-m-d" />
  """
  attr(:id, :any, default: nil)
  attr(:name, :any, default: nil)
  attr(:label, :string, default: nil)
  attr(:value, :any, default: nil)
  attr(:mode, :string, default: "single", doc: "flatpickr mode: single, range, or multiple")
  attr(:date_format, :string, default: "Y-m-d", doc: "flatpickr dateFormat option")
  attr(:enable_time, :boolean, default: false, doc: "whether to enable time selection")
  attr(:time_24hr, :boolean, default: false, doc: "whether to show time in 24-hour format")
  attr(:minute_increment, :integer, default: nil, doc: "minute step for time selection")
  attr(:alt_input, :boolean, default: false, doc: "whether to show a formatted display input")
  attr(:alt_format, :string, default: nil, doc: "flatpickr altFormat option")
  attr(:min_date, :string, default: nil, doc: "minimum selectable date (flatpickr format)")
  attr(:max_date, :string, default: nil, doc: "maximum selectable date (flatpickr format)")
  attr(:placeholder, :string, default: nil)
  attr(:required, :boolean, default: false)
  attr(:disabled, :boolean, default: false)
  attr(:class, :any, default: nil)
  attr(:error_class, :any, default: nil)

  attr(:push_event, :string,
    default: nil,
    doc: "if set, use pushEvent instead of form phx-change"
  )

  attr(:push_key, :string, default: "date", doc: "key used in the pushed event map")

  attr(:field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:start_date]"
  )

  attr(:errors, :list, default: [])

  def date_picker(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    required =
      assigns[:required] ||
        case field.form.source do
          %Ecto.Changeset{required: required_fields} -> field.field in required_fields
          _ -> false
        end

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign(:required, required)
    |> assign(:name, assigns.name || field.name)
    |> assign(:value, if(is_nil(assigns.value), do: field.value, else: assigns.value))
    |> date_picker()
  end

  def date_picker(assigns) do
    fp_opts =
      %{
        mode: assigns.mode,
        dateFormat: assigns.date_format,
        enableTime: assigns.enable_time
      }
      |> then(fn opts ->
        if assigns.min_date, do: Map.put(opts, :minDate, assigns.min_date), else: opts
      end)
      |> then(fn opts ->
        if assigns.max_date, do: Map.put(opts, :maxDate, assigns.max_date), else: opts
      end)
      |> then(fn opts ->
        if assigns.enable_time, do: Map.put(opts, :time_24hr, assigns.time_24hr), else: opts
      end)
      |> then(fn opts ->
        if assigns.minute_increment,
          do: Map.put(opts, :minuteIncrement, assigns.minute_increment),
          else: opts
      end)
      |> then(fn opts ->
        if assigns.alt_input, do: Map.put(opts, :altInput, assigns.alt_input), else: opts
      end)
      |> then(fn opts ->
        if assigns.alt_format, do: Map.put(opts, :altFormat, assigns.alt_format), else: opts
      end)
      |> Jason.encode!()

    assigns = assign(assigns, :fp_opts, fp_opts)

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">
          {@label}<span :if={@required} class="text-error ml-0.5">*</span>
        </span>
      </label>
      <%!-- phx-update="ignore" protects flatpickr's DOM from LiveView re-renders --%>
      <div id={"#{@id}-fp"} phx-update="ignore">
        <input
          type="text"
          id={@id}
          name={@name}
          value={@value}
          placeholder={@placeholder}
          required={@required}
          disabled={@disabled}
          data-flatpickr-opts={@fp_opts}
          data-push-event={@push_event}
          data-push-key={@push_key}
          phx-hook="Flatpickr"
          class={[
            @class || "w-full input text-base-content",
            @errors != [] && (@error_class || "input-error")
          ]}
          readonly
        />
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a full Tiptap rich text editor backed by a hidden form input.
  """
  attr(:id, :any, default: nil)
  attr(:name, :any, default: nil)
  attr(:label, :string, default: nil)
  attr(:value, :any, default: nil)
  attr(:placeholder, :string, default: nil)
  attr(:required, :boolean, default: false)
  attr(:class, :any, default: nil)
  attr(:fill_height, :boolean, default: false)

  attr(:field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:notes]"
  )

  attr(:errors, :list, default: [])

  def rich_text_input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    required =
      assigns[:required] ||
        case field.form.source do
          %Ecto.Changeset{required: required_fields} -> field.field in required_fields
          _ -> false
        end

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign(:required, required)
    |> assign(:name, assigns.name || field.name)
    |> assign(:value, if(is_nil(assigns.value), do: field.value, else: assigns.value))
    |> rich_text_input()
  end

  def rich_text_input(assigns) do
    assigns = assign(assigns, :value, assigns.value || "")

    ~H"""
    <div class={["fieldset mb-2", @fill_height && "flex h-full min-h-0 flex-col"]}>
      <label for={@id} class="flex flex-col gap-2">
        <span :if={@label} class="label">
          {@label}<span :if={@required} class="text-error ml-0.5">*</span>
        </span>
      </label>

      <div
        id={"#{@id}-wrapper"}
        phx-hook="TipTapRichText"
        phx-update="ignore"
        data-unsaved-source={@id}
        data-placeholder={@placeholder}
        class={[
          @class,
          "tiptap-component relative flex min-h-[360px] flex-col overflow-hidden rounded-xl border bg-base-100 shadow-sm transition-colors",
          @fill_height && "min-h-0 flex-1",
          @errors == [] && "border-base-content/15 focus-within:border-primary/60",
          @errors != [] && "border-error"
        ]}
      >
        <input
          type="hidden"
          id={@id}
          name={@name}
          value={@value}
          required={@required}
          data-tiptap-input
        />

        <div
          id={"#{@id}-toolbar"}
          role="toolbar"
          aria-label={gettext("Toolbar")}
          class="tiptap-toolbar sticky top-0 z-10 flex flex-wrap items-center gap-1 border-b border-base-content/10 bg-base-200/50 p-2"
        >
          <button
            type="button"
            class="tiptap-button min-w-32 justify-start gap-1.5 px-2"
            data-action="heading-toggle"
            title={gettext("Text style")}
          >
            <.icon name="icon-[tabler--typography]" class="size-4" />
            <span data-heading-label class="truncate text-xs">{gettext("Normal Text")}</span>
            <.icon name="icon-[tabler--chevron-down]" class="ml-auto size-3.5" />
          </button>

          <div class="tiptap-separator" />

          <button type="button" class="tiptap-button" data-action="bold" title={gettext("Bold")}>
            <.icon name="icon-[tabler--bold]" class="size-4" />
          </button>
          <button type="button" class="tiptap-button" data-action="italic" title={gettext("Italic")}>
            <.icon name="icon-[tabler--italic]" class="size-4" />
          </button>
          <button
            type="button"
            class="tiptap-button"
            data-action="strike"
            title={gettext("Strikethrough")}
          >
            <.icon name="icon-[tabler--strikethrough]" class="size-4" />
          </button>
          <button
            type="button"
            class="tiptap-button"
            data-action="underline"
            title={gettext("Underline")}
          >
            <.icon name="icon-[tabler--underline]" class="size-4" />
          </button>
          <button
            type="button"
            class="tiptap-button"
            data-action="highlight"
            title={gettext("Highlight")}
          >
            <.icon name="icon-[tabler--highlight]" class="size-4" />
          </button>

          <div class="tiptap-separator" />

          <button
            type="button"
            class="tiptap-button"
            data-action="align-left"
            title={gettext("Align left")}
          >
            <.icon name="icon-[tabler--align-left]" class="size-4" />
          </button>
          <button
            type="button"
            class="tiptap-button"
            data-action="align-center"
            title={gettext("Align center")}
          >
            <.icon name="icon-[tabler--align-center]" class="size-4" />
          </button>
          <button
            type="button"
            class="tiptap-button"
            data-action="align-right"
            title={gettext("Align right")}
          >
            <.icon name="icon-[tabler--align-right]" class="size-4" />
          </button>
          <button
            type="button"
            class="tiptap-button"
            data-action="align-justify"
            title={gettext("Justify")}
          >
            <.icon name="icon-[tabler--align-justified]" class="size-4" />
          </button>

          <div class="tiptap-separator" />

          <button
            type="button"
            class="tiptap-button"
            data-action="bulletList"
            title={gettext("Bullet list")}
          >
            <.icon name="icon-[tabler--list]" class="size-4" />
          </button>
          <button
            type="button"
            class="tiptap-button"
            data-action="orderedList"
            title={gettext("Numbered list")}
          >
            <.icon name="icon-[tabler--list-numbers]" class="size-4" />
          </button>
          <button
            type="button"
            class="tiptap-button"
            data-action="codeblock"
            title={gettext("Code block")}
          >
            <.icon name="icon-[tabler--code]" class="size-4" />
          </button>
          <button
            type="button"
            class="tiptap-button"
            data-action="blockquote"
            title={gettext("Quote")}
          >
            <.icon name="icon-[tabler--quote]" class="size-4" />
          </button>
          <button type="button" class="tiptap-button" data-action="link" title={gettext("Link")}>
            <.icon name="icon-[tabler--link]" class="size-4" />
          </button>

          <div class="tiptap-separator" />

          <button type="button" class="tiptap-button" data-action="undo" title={gettext("Undo")}>
            <.icon name="icon-[tabler--arrow-back-up]" class="size-4" />
          </button>
          <button type="button" class="tiptap-button" data-action="redo" title={gettext("Redo")}>
            <.icon name="icon-[tabler--arrow-forward-up]" class="size-4" />
          </button>
        </div>

        <div class="flex-1 overflow-y-auto">
          <div id={"#{@id}-editor"} data-tiptap-editor />
        </div>

        <div
          data-link-popover
          class="tiptap-popover hidden z-50 min-w-72 max-w-sm flex-col gap-3 rounded-lg border border-base-content/15 bg-base-100 p-3 shadow-xl"
        >
          <label
            for={"#{@id}-link-text"}
            class="flex flex-col gap-1 text-xs font-medium text-base-content/60"
          >
            {gettext("Text")}
            <input
              id={"#{@id}-link-text"}
              type="text"
              data-link-input
              data-link-text
              class="input input-sm w-full"
              placeholder={gettext("Link text")}
            />
          </label>
          <label
            for={"#{@id}-link-url"}
            class="flex flex-col gap-1 text-xs font-medium text-base-content/60"
          >
            {gettext("URL")}
            <input
              id={"#{@id}-link-url"}
              type="text"
              data-link-input
              data-link-url
              class="input input-sm w-full"
              placeholder="https://example.com"
            />
          </label>
          <div class="flex items-center justify-between">
            <button type="button" class="tiptap-popover-button" data-link-open title={gettext("Open")}>
              <.icon name="icon-[tabler--external-link]" class="size-4" />
            </button>
            <div class="flex items-center gap-1">
              <button
                type="button"
                class="tiptap-popover-button"
                data-link-remove
                title={gettext("Remove link")}
              >
                <.icon name="icon-[tabler--ban]" class="size-4" />
              </button>
              <button
                type="button"
                class="tiptap-popover-button"
                data-link-apply
                title={gettext("Apply")}
              >
                <.icon name="icon-[tabler--check]" class="size-4" />
              </button>
            </div>
          </div>
        </div>

        <div
          data-highlight-popover
          class="tiptap-popover hidden z-50 items-center gap-1 rounded-lg border border-base-content/15 bg-base-100 p-2 shadow-xl"
        >
          <button
            :for={{name, color} <- highlight_colors()}
            type="button"
            class="tiptap-swatch"
            data-highlight-color={color}
            title={name}
          >
            <span
              class="block size-5 rounded-full border border-base-content/15"
              style={"background-color: #{color}"}
            />
          </button>
          <div class="tiptap-separator" />
          <button
            type="button"
            class="tiptap-popover-button"
            data-highlight-color="unset"
            title={gettext("Remove")}
          >
            <.icon name="icon-[tabler--ban]" class="size-4" />
          </button>
        </div>

        <div
          data-emoji-popover
          class="tiptap-popover tiptap-popover-grid hidden z-50 w-72 grid-cols-10 gap-1 rounded-lg border border-base-content/15 bg-base-100 p-2 shadow-xl"
        >
          <button
            :for={emoji <- emoji_options()}
            type="button"
            class="tiptap-popover-button justify-center text-base"
            data-emoji={emoji}
            title={emoji}
          >
            {emoji}
          </button>
        </div>

        <div
          data-heading-popover
          class="tiptap-popover hidden z-50 w-44 flex-col gap-1 rounded-lg border border-base-content/15 bg-base-100 p-2 shadow-xl"
        >
          <button
            :for={{label, level, icon} <- heading_options()}
            type="button"
            class="tiptap-menu-button"
            data-heading-level={level}
          >
            <.icon name={icon} class="size-4" />
            {label}
          </button>
        </div>
      </div>

      <div
        :if={@errors != []}
        id={"#{@id}-error"}
        role="alert"
        class="mt-2 flex shrink-0 items-center gap-2 rounded-md border border-error/20 bg-error/8 px-3 py-2 text-xs font-medium text-error"
      >
        <.icon name="icon-[tabler--alert-circle]" class="size-4 shrink-0" />
        <span>{Enum.join(@errors, ", ")}</span>
      </div>
    </div>
    """
  end

  defp heading_options do
    [
      {gettext("Normal Text"), 0, "icon-[tabler--typography]"},
      {gettext("Heading 1"), 1, "icon-[tabler--h-1]"},
      {gettext("Heading 2"), 2, "icon-[tabler--h-2]"},
      {gettext("Heading 3"), 3, "icon-[tabler--h-3]"},
      {gettext("Heading 4"), 4, "icon-[tabler--h-4]"}
    ]
  end

  defp highlight_colors do
    [
      {gettext("Yellow"), "#fff3bf"},
      {gettext("Orange"), "#ffe0b2"},
      {gettext("Blue"), "#cce5ff"},
      {gettext("Green"), "#d3f9d8"},
      {gettext("Red"), "#ffc9c9"},
      {gettext("Grey"), "#e9ecef"}
    ]
  end

  defp emoji_options do
    ~w(😀 😄 😁 😂 🙂 😊 😍 😎 🤔 😅 👍 🙌 👋 🙏 💪 ❤️ 💙 🎉 🚀 ✅ ⭐ 🔥 💡 📌 👀 ✨ ☕ 📎 📝)
  end

  # Helper used by inputs to generate form errors
  def error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <span class="icon-[tabler--alert-circle] size-5" /> {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot(:inner_block, required: true)
  slot(:subtitle)
  slot(:actions)

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">{render_slot(@inner_block)}</h1>

        <p :if={@subtitle != []} class="text-sm text-base-content/70">{render_slot(@subtitle)}</p>
      </div>

      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:row_id, :any, default: nil, doc: "the function for generating the row id")
  attr(:row_click, :any, default: nil, doc: "the function for handling phx-click on each row")

  attr(:row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"
  )

  slot :col, required: true do
    attr(:label, :string)
  end

  slot(:action, doc: "the slot for showing user actions in the last table column")

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead class="bg-base-200 text-base-content/70 text-xs uppercase">
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>

          <th :if={@action != []}><span class="sr-only">{gettext("Actions")}</span></th>
        </tr>
      </thead>

      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>

          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr(:title, :string, required: true)
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>

          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders an icon using the Iconify CSS classes.

  Icons are rendered via the `@iconify/tailwind4` plugin. Use any icon set
  available at https://icon-sets.iconify.design by passing the full class name
  as the `name` attribute.

  ## Examples

      <.icon name="icon-[tabler--x]" />
      <.icon name="icon-[tabler--refresh]" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr(:name, :string, required: true)
  attr(:class, :any, default: "size-4")
  attr(:rest, :global)

  def icon(assigns) do
    ~H"""
    <span class={[@name, @class]} {@rest} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(KonevoWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(KonevoWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Company search select using live_select. Dropdown opens instantly via CSS; parent handles
  `"live_select_change"` events to update options via `send_update(LiveSelect.Component, ...)`.
  """
  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:myself, :any, required: true)
  attr(:label, :string, default: nil)
  attr(:options, :list, default: [])
  attr(:required, :boolean, default: false)

  def company_select(assigns) do
    nil_option = %{label: gettext("No company"), value: nil}
    options = if assigns.required, do: assigns.options, else: [nil_option | assigns.options]

    assigns =
      assigns
      |> assign(:live_select_options, options)
      |> assign(:selected_option, selected_live_select_option(options, assigns.field.value))

    ~H"""
    <div class="fieldset flex w-full flex-col gap-2">
      <span :if={@label} class="label">{@label}</span>
      <div class="group relative w-full">
        <span class="pointer-events-none absolute inset-y-0 left-3 z-20 flex items-center">
          <span class="flex size-6 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
            <.icon name="icon-[tabler--building]" class="size-3.5" />
          </span>
        </span>
        <.live_select
          field={@field}
          options={@live_select_options}
          value={@selected_option || @field.value}
          value_mapper={&live_select_option_value(&1, @live_select_options)}
          phx-target={@myself}
          placeholder={gettext("Search companies…")}
          style={:none}
          debounce={150}
          update_min_len={1}
          container_class="relative w-full"
          text_input_class="input h-10 w-full cursor-pointer pl-11 pr-12 font-medium placeholder:text-base-content/40 focus:cursor-text"
          dropdown_class="absolute left-0 top-[calc(100%+4px)] z-[300] w-full max-h-60 overflow-y-auto rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-xl shadow-base-content/10"
          option_class="flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-sm"
          available_option_class="cursor-pointer rounded-md hover:bg-base-200/70"
          selected_option_class="cursor-pointer rounded-md bg-base-200/70 font-semibold"
          active_option_class="bg-base-200"
        >
          <:option :let={opt}>
            <span class="flex size-6 shrink-0 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
              <.icon
                name={
                  if(is_nil(opt.value), do: "icon-[tabler--ban]", else: "icon-[tabler--building]")
                }
                class="size-3"
              />
            </span>
            <span class={[
              "min-w-0 flex-1 truncate",
              is_nil(opt.value) && "italic text-base-content/40"
            ]}>
              {opt.label}
            </span>
          </:option>
        </.live_select>
        <span
          id={"#{@field.id}-select-chevron"}
          class="pointer-events-none absolute inset-y-0 right-2 z-20 flex items-center text-base-content/45"
        >
          <.icon
            name="icon-[tabler--chevron-down]"
            class="size-4 transition-transform duration-200 group-focus-within:rotate-180"
          />
        </span>
      </div>
    </div>
    """
  end

  defp selected_live_select_option(_options, value) when value in [nil, ""], do: nil

  defp selected_live_select_option(options, value) do
    Enum.find(options, &(to_string(&1.value) == to_string(value)))
  end

  defp live_select_option_value(value, options) when is_binary(value) do
    Enum.find_value(options, value, fn option ->
      if to_string(option.value) == value, do: option.value
    end)
  end

  defp live_select_option_value(value, _options), do: value

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Contact search select using live_select. Dropdown opens instantly via CSS; parent handles
  `"live_select_change"` events to update options via `send_update(LiveSelect.Component, ...)`.
  `"contact_select"` (params `%{"value" => id, "label" => label}`).
  """
  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:myself, :any, required: true)
  attr(:label, :string, default: nil)
  attr(:options, :list, default: [])
  attr(:required, :boolean, default: false)
  attr(:show_errors, :boolean, default: nil)

  def contact_select(assigns) do
    show_errors =
      if is_nil(assigns.show_errors),
        do: Phoenix.Component.used_input?(assigns.field),
        else: assigns.show_errors

    errors =
      if show_errors do
        Enum.map(assigns.field.errors, &translate_error/1)
      else
        []
      end

    nil_option = %{label: gettext("\u2014 No contact \u2014"), value: nil}
    options = if assigns.required, do: assigns.options, else: [nil_option | assigns.options]

    assigns =
      assigns
      |> assign(:errors, errors)
      |> assign(:live_select_options, options)
      |> assign(:selected_option, selected_live_select_option(options, assigns.field.value))

    ~H"""
    <div class="fieldset flex w-full flex-col gap-2">
      <span :if={@label} id={"#{@field.id}-label"} class="label">
        {@label}<span :if={@required} class="ml-0.5 text-error" aria-hidden="true">*</span>
      </span>
      <div class="group relative w-full">
        <span class="pointer-events-none absolute inset-y-0 left-3 z-20 flex items-center">
          <span class="flex size-6 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
            <.icon name="icon-[tabler--user]" class="size-3.5" />
          </span>
        </span>
        <.live_select
          field={@field}
          options={@live_select_options}
          value={@selected_option || @field.value}
          value_mapper={&live_select_option_value(&1, @live_select_options)}
          phx-target={@myself}
          placeholder={gettext("Search contacts…")}
          style={:none}
          debounce={150}
          update_min_len={1}
          container_class="relative w-full"
          text_input_class="input w-full cursor-pointer pl-11 pr-12 font-medium placeholder:text-base-content/40 focus:cursor-text"
          dropdown_class="absolute left-0 top-[calc(100%+4px)] z-[300] w-full max-h-60 overflow-y-auto rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-xl shadow-base-content/10"
          option_class="flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-sm"
          available_option_class="cursor-pointer rounded-md hover:bg-base-200/70"
          selected_option_class="cursor-pointer rounded-md bg-base-200/70 font-semibold"
          active_option_class="bg-base-200"
        >
          <:option :let={opt}>
            <span class="flex size-6 shrink-0 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
              <.icon
                name={if(is_nil(opt.value), do: "icon-[tabler--ban]", else: "icon-[tabler--user]")}
                class="size-3"
              />
            </span>
            <span class={[
              "min-w-0 flex-1 truncate",
              is_nil(opt.value) && "italic text-base-content/40"
            ]}>
              {opt.label}
            </span>
          </:option>
        </.live_select>
        <span
          id={"#{@field.id}-select-chevron"}
          class="pointer-events-none absolute inset-y-0 right-2 z-20 flex items-center text-base-content/45"
        >
          <.icon
            name="icon-[tabler--chevron-down]"
            class="size-4 transition-transform duration-200 group-focus-within:rotate-180"
          />
        </span>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end
end
