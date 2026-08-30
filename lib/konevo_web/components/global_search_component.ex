defmodule KonevoWeb.GlobalSearchComponent do
  @moduledoc false

  use KonevoWeb, :live_component

  alias Konevo.Search

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:open?, false)
     |> assign(:results, [])
     |> assign(:form, search_form(""))}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("focus", _params, socket) do
    {:noreply, assign(socket, :open?, true)}
  end

  def handle_event("close", _params, socket) do
    {:noreply,
     socket
     |> assign(:open?, false)
     |> assign(:results, [])
     |> assign(:form, search_form(""))}
  end

  def handle_event("search", %{"global_search" => %{"q" => query}}, socket) do
    query = String.trim(query)

    case Search.search(socket.assigns.current_scope, query) do
      {:ok, results} ->
        {:noreply,
         socket
         |> assign(:open?, true)
         |> assign(:results, results)
         |> assign(:form, search_form(query))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:results, [])
         |> put_flash(:error, gettext("Unable to search right now."))}
    end
  end

  def handle_event("open_first", _params, %{assigns: %{results: [result | _]}} = socket) do
    {:noreply, push_navigate(socket, to: result_path(result))}
  end

  def handle_event("open_first", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook=".GlobalSearchShortcut" class="relative w-full">
      <.form
        for={@form}
        id="global-search-form"
        phx-change="search"
        phx-submit="open_first"
        phx-target={@myself}
        class="[&_.fieldset]:mb-0 [&_.fieldset]:min-w-0 [&_.fieldset]:flex-1 [&_label]:block"
      >
        <div class="input flex h-9 w-full max-w-none items-center gap-2 px-2.5 text-base-content !border-base-content/15 bg-base-100 !shadow-sm transition-colors focus-within:!border-base-content/15 focus-within:!bg-base-100 focus-within:!shadow-sm focus-within:!outline-none focus-within:!ring-0 sm:h-10 sm:gap-3 sm:px-3">
          <.icon name="icon-[tabler--search]" class="size-4 shrink-0 text-base-content/55 sm:size-5" />
          <.input
            field={@form[:q]}
            id="global-search-input"
            type="search"
            placeholder={gettext("Search workspace")}
            autocomplete="off"
            aria-label={gettext("Search workspace")}
            phx-debounce="200"
            phx-focus="focus"
            phx-target={@myself}
            class="h-9 min-w-0 grow border-0 bg-transparent px-0 text-[13px] outline-none placeholder:text-base-content/45 focus:outline-none sm:h-10 sm:text-sm"
          />
          <span class="my-auto hidden shrink-0 gap-1.5 sm:flex">
            <kbd class="kbd kbd-sm bg-base-200 text-base-content/65">{gettext("Ctrl")}</kbd>
            <kbd class="kbd kbd-sm bg-base-200 text-base-content/65">{gettext("K")}</kbd>
          </span>
        </div>
      </.form>

      <section
        :if={@open? && @form[:q].value != ""}
        id="global-search-results"
        class="absolute left-0 top-[calc(100%+0.5rem)] z-70 w-full overflow-hidden rounded-lg border border-base-content/15 bg-base-100 p-2 shadow-2xl shadow-base-content/15"
        aria-label={gettext("Search results")}
      >
        <p :if={@results == []} class="px-3 py-8 text-center text-sm text-base-content/55">
          {gettext("No matching records")}
        </p>
        <div :if={@results != []} class="max-h-[min(32rem,calc(100vh-6rem))] overflow-y-auto">
          <.link
            :for={result <- @results}
            id={"global-search-result-#{result.type}-#{result.id}"}
            navigate={result_path(result)}
            class="flex items-center gap-3 rounded-md px-3 py-2.5 transition-colors hover:bg-base-200/80 focus:bg-base-200/80 focus:outline-none"
          >
            <span class={[
              "flex size-9 shrink-0 items-center justify-center rounded-md ring-1",
              result_icon_class(result.type)
            ]}>
              <.icon name={result_icon(result.type)} class="size-4.5" />
            </span>
            <span class="min-w-0 flex-1">
              <span class="block truncate text-sm font-medium text-base-content">{result.title}</span>
              <span :if={result.subtitle != ""} class="block truncate text-xs text-base-content/55">
                {result.subtitle}
              </span>
            </span>
            <span class={[
              "shrink-0 rounded-full px-2 py-0.5 text-[0.68rem] font-bold uppercase ring-1",
              result_badge_class(result.type)
            ]}>
              {result_label(result.type)}
            </span>
          </.link>
        </div>
      </section>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".GlobalSearchShortcut">
        export default {
          mounted() {
            this.handleKeydown = event => {
              if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
                event.preventDefault()
                document.getElementById("global-search-input")?.focus()
                this.pushEventTo("#global-search", "focus", {})
              }

              if (event.key === "Escape") {
                document.getElementById("global-search-input")?.blur()
                this.pushEventTo("#global-search", "close", {})
              }
            }

            window.addEventListener("keydown", this.handleKeydown)
          },
          destroyed() {
            window.removeEventListener("keydown", this.handleKeydown)
          }
        }
      </script>
    </div>
    """
  end

  defp search_form(query), do: to_form(%{"q" => query}, as: :global_search)

  defp result_path(%{type: :contact, id: id}), do: ~p"/contacts/#{id}"
  defp result_path(%{type: :company, id: id}), do: ~p"/companies/#{id}"
  defp result_path(%{type: :deal, id: id}), do: ~p"/deals/#{id}/edit"
  defp result_path(%{type: :task, id: id}), do: ~p"/tasks/#{id}"
  defp result_path(%{type: :thread, id: id}), do: ~p"/inbox/#{id}"

  defp result_icon(:contact), do: "icon-[tabler--user]"
  defp result_icon(:company), do: "icon-[tabler--building]"
  defp result_icon(:deal), do: "icon-[tabler--briefcase]"
  defp result_icon(:task), do: "icon-[tabler--checkbox]"
  defp result_icon(:thread), do: "icon-[tabler--inbox]"

  defp result_icon_class(:contact), do: "bg-success/10 text-success ring-success/20"
  defp result_icon_class(:company), do: "bg-secondary/10 text-secondary ring-secondary/20"
  defp result_icon_class(:deal), do: "bg-warning/15 text-warning ring-warning/25"
  defp result_icon_class(:task), do: "bg-accent/10 text-accent ring-accent/20"
  defp result_icon_class(:thread), do: "bg-info/10 text-info ring-info/20"

  defp result_badge_class(:contact), do: "bg-success/10 text-success ring-success/20"
  defp result_badge_class(:company), do: "bg-secondary/10 text-secondary ring-secondary/20"
  defp result_badge_class(:deal), do: "bg-warning/15 text-warning ring-warning/25"
  defp result_badge_class(:task), do: "bg-accent/10 text-accent ring-accent/20"
  defp result_badge_class(:thread), do: "bg-info/10 text-info ring-info/20"

  defp result_label(:contact), do: gettext("Contact")
  defp result_label(:company), do: gettext("Company")
  defp result_label(:deal), do: gettext("Deal")
  defp result_label(:task), do: gettext("Task")
  defp result_label(:thread), do: gettext("Inbox")
end
