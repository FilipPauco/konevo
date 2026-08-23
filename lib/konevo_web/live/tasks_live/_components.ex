defmodule KonevoWeb.TasksLive.Components do
  use KonevoWeb, :html

  attr :id, :string, required: true
  attr :tasks, :list, required: true
  attr :empty_message, :string, required: true
  attr :show_contact?, :boolean, default: false

  def task_timeline(assigns) do
    timeline_tasks = sort_timeline_tasks(assigns.tasks)

    assigns =
      assigns
      |> assign(:timeline_tasks, timeline_tasks)
      |> assign(:timeline_count, length(timeline_tasks))

    ~H"""
    <div id={@id}>
      <div
        :if={@timeline_tasks == []}
        class="flex flex-col items-center justify-center px-5 py-10 text-center"
      >
        <.icon name="icon-[tabler--checklist]" class="mb-2 size-8 text-base-content/15" />
        <p class="text-xs leading-relaxed text-base-content/35">{@empty_message}</p>
      </div>

      <ul
        :if={@timeline_tasks != []}
        class="konevo-task-timeline timeline timeline-snap-icon timeline-compact timeline-vertical w-full px-4 py-3"
      >
        <%= for {task, index} <- Enum.with_index(@timeline_tasks) do %>
          <li id={"#{@id}-task-#{task.id}"}>
            <hr :if={index > 0} class={timeline_line_class(task.status)} />
            <div class="timeline-middle px-0">
              <span class={timeline_icon_ring_class(task.status)}>
                <span class={timeline_icon_dot_class(task.status)}></span>
              </span>
            </div>
            <div class="timeline-end m-3 ms-2 w-full rounded-lg">
              <div class="mb-3 flex min-w-0 gap-2 pt-0.5 font-medium max-sm:flex-col-reverse sm:items-center sm:justify-between">
                <.link
                  navigate={~p"/tasks/#{task.id}"}
                  class="min-w-0 truncate text-sm font-semibold text-base-content transition-colors hover:text-primary hover:underline"
                >
                  {task.title}
                </.link>
                <div class="shrink-0 whitespace-nowrap text-right leading-tight max-sm:text-left">
                  <span class="block text-xs font-semibold text-base-content/70">
                    {task_due_date(task)}
                  </span>
                  <span
                    :if={task_due_time(task)}
                    class="block text-[0.6875rem] font-normal text-base-content/35"
                  >
                    {task_due_time(task)}
                  </span>
                </div>
              </div>

              <p
                :if={task.description not in [nil, ""]}
                class="mb-2 line-clamp-2 text-xs text-base-content/55"
              >
                {task.description}
              </p>

              <div class="flex flex-wrap items-center gap-2 text-xs text-base-content/45">
                <span class={status_badge_class(task.status)}>
                  {task_status(task)}
                </span>
                <span :if={task.assigned_to} class="inline-flex min-w-0 items-center gap-1">
                  <.icon name="icon-[tabler--user]" class="size-3.5 shrink-0" />
                  <span class="max-w-32 truncate">{task.assigned_to.email}</span>
                </span>
                <.link
                  :if={@show_contact? && task.contact}
                  navigate={~p"/contacts/#{task.contact}"}
                  class="inline-flex min-w-0 items-center gap-1 transition-colors hover:text-primary hover:underline"
                >
                  <.icon name="icon-[tabler--address-book]" class="size-3.5 shrink-0" />
                  <span class="max-w-28 truncate">{contact_name(task.contact)}</span>
                </.link>
                <span :if={task.deal} class="inline-flex min-w-0 items-center gap-1">
                  <.icon name="icon-[tabler--briefcase]" class="size-3.5 shrink-0" />
                  <span class="max-w-28 truncate">{task.deal.title}</span>
                </span>
              </div>
            </div>
            <hr :if={index < @timeline_count - 1} class={timeline_line_class(task.status)} />
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp task_due_date(%{due_date: %DateTime{} = due_date}) do
    Calendar.strftime(due_date, "%B %-d, %Y")
  end

  defp task_due_date(_task), do: gettext("No due date")

  defp task_due_time(%{due_date: %DateTime{} = due_date}),
    do: Calendar.strftime(due_date, "%H:%M")

  defp task_due_time(_task), do: nil

  defp sort_timeline_tasks(tasks), do: Enum.sort_by(tasks, &timeline_sort_key/1, :desc)

  defp timeline_sort_key(task) do
    {timeline_due_date_sort_value(task.due_date), task.id || 0}
  end

  defp timeline_due_date_sort_value(%DateTime{} = due_date), do: DateTime.to_unix(due_date)
  defp timeline_due_date_sort_value(_due_date), do: -9_999_999_999

  defp contact_name(contact) do
    [contact.first_name, contact.last_name]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> case do
      "" -> contact.email || gettext("Unknown contact")
      name -> name
    end
  end

  defp task_status(%{status: status}), do: status |> Atom.to_string() |> Phoenix.Naming.humanize()

  defp timeline_icon_ring_class(:done),
    do: "flex size-4.5 items-center justify-center rounded-full bg-success/20"

  defp timeline_icon_ring_class(:cancelled),
    do: "flex size-4.5 items-center justify-center rounded-full bg-base-content/10"

  defp timeline_icon_ring_class(:in_progress),
    do: "flex size-4.5 items-center justify-center rounded-full bg-primary/20"

  defp timeline_icon_ring_class(_status),
    do: "flex size-4.5 items-center justify-center rounded-full bg-primary/20"

  defp timeline_icon_dot_class(:done), do: "badge badge-success size-3 rounded-full p-0"
  defp timeline_icon_dot_class(:cancelled), do: "badge badge-error size-3 rounded-full p-0"
  defp timeline_icon_dot_class(:in_progress), do: "badge badge-info size-3 rounded-full p-0"
  defp timeline_icon_dot_class(_status), do: "badge badge-primary size-3 rounded-full p-0"

  defp timeline_line_class(:done), do: "bg-success"
  defp timeline_line_class(:cancelled), do: "bg-base-content/15"
  defp timeline_line_class(:in_progress), do: "bg-primary/60"
  defp timeline_line_class(_status), do: "bg-primary/60"

  defp status_badge_class(:done), do: "badge badge-success badge-sm"
  defp status_badge_class(:cancelled), do: "badge badge-error badge-sm"
  defp status_badge_class(:in_progress), do: "badge badge-info badge-sm"
  defp status_badge_class(_status), do: "badge badge-primary badge-sm"
end
