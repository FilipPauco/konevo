defmodule KonevoWeb.TasksLive.Index do
  use KonevoWeb, :live_view

  alias Konevo.Tasks
  alias Konevo.Tasks.Task
  alias Konevo.Uploads
  alias KonevoWeb.TasksLive.DrawerComponent

  @per_page 25
  @all_statuses [:open, :in_progress, :done, :cancelled]
  @all_priorities [:low, :normal, :high, :urgent]
  @sortable_columns ~w(title due_date priority inserted_at)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, gettext("Tasks"))
      |> assign(:loading, true)
      |> assign(:task_rows, [])
      |> assign(:task_types, [])
      |> assign(:task_options, [])
      |> assign(:expanded_task_ids, MapSet.new())
      |> assign(:task, nil)
      |> assign(:parent_task_id, nil)
      |> assign(:drawer_task_id, nil)
      |> assign(:drawer_refresh, 0)
      # filter state
      |> assign(:search, "")
      |> assign(:archive_filter, :active)
      |> assign(:statuses, [])
      |> assign(:priorities, [])
      |> assign(:due_from, "")
      |> assign(:due_to, "")
      |> assign(:overdue, false)
      |> assign(:sort_by, :due_date)
      |> assign(:sort_dir, :asc)
      |> assign(:page, 1)
      |> assign(:total, 0)
      |> assign(:tasks_request_ref, nil)
      |> assign(:filter_mode, false)
      |> assign(:confirm_delete_task_id, nil)
      |> assign(:confirm_delete_has_children, false)
      |> stream(:tasks, [])

    if connected?(socket), do: send(self(), :load_task_tree)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket = apply_action(socket, socket.assigns.live_action, params)
    socket = apply_filter_params(socket, params)
    {:noreply, socket}
  end

  defp apply_filter_params(socket, params) do
    %{
      search: search,
      archive_filter: archive_filter,
      statuses: statuses,
      priorities: priorities,
      due_from: due_from,
      due_to: due_to,
      overdue: overdue,
      sort_by: sort_by,
      sort_dir: sort_dir,
      page: page
    } = parse_filter_params(params)

    filter_mode =
      filter_mode?(search, archive_filter, statuses, priorities, due_from, due_to, overdue)

    socket =
      socket
      |> assign(:search, search)
      |> assign(:archive_filter, archive_filter)
      |> assign(:statuses, statuses)
      |> assign(:priorities, priorities)
      |> assign(:due_from, due_from)
      |> assign(:due_to, due_to)
      |> assign(:overdue, overdue)
      |> assign(:sort_by, sort_by)
      |> assign(:sort_dir, sort_dir)
      |> assign(:page, page)
      |> assign(:filter_mode, filter_mode)

    if filter_mode do
      load_filtered_tasks(socket)
    else
      if connected?(socket) do
        reload_tree(socket)
      else
        socket
      end
    end
  end

  defp parse_filter_params(params) do
    %{
      search: Map.get(params, "search", ""),
      archive_filter: parse_archive_filter(Map.get(params, "archived", "")),
      statuses: parse_list_param(params, "statuses", @all_statuses),
      priorities: parse_list_param(params, "priorities", @all_priorities),
      due_from: parse_date_param(Map.get(params, "due_from", "")),
      due_to: parse_date_param(Map.get(params, "due_to", "")),
      overdue: Map.get(params, "overdue") == "true",
      sort_by: parse_sort_by(Map.get(params, "sort_by", "")),
      sort_dir: parse_sort_dir(Map.get(params, "sort_dir", "")),
      page: parse_page(Map.get(params, "page", ""))
    }
  end

  defp parse_list_param(params, key, valid_atoms) do
    str = Map.get(params, key, "")
    valid_strings = Enum.map(valid_atoms, &Atom.to_string/1)

    str
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn s ->
      if s in valid_strings, do: [String.to_existing_atom(s)], else: []
    end)
  end

  defp parse_date_param(str) when is_binary(str) and str != "" do
    case Date.from_iso8601(str) do
      {:ok, _} -> str
      _ -> ""
    end
  end

  defp parse_date_param(_), do: ""

  defp parse_archive_filter("archived"), do: :archived
  defp parse_archive_filter("all"), do: :all
  defp parse_archive_filter(_), do: :active

  defp parse_sort_by(col) when col in @sortable_columns, do: String.to_existing_atom(col)
  defp parse_sort_by(_), do: :due_date

  defp parse_sort_dir("desc"), do: :desc
  defp parse_sort_dir(_), do: :asc

  defp parse_page(str) when is_binary(str) and str != "" do
    case Integer.parse(str) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  defp filter_mode?(search, _archive_filter, statuses, priorities, due_from, due_to, overdue) do
    search != "" or statuses != [] or priorities != [] or
      due_from != "" or due_to != "" or overdue
  end

  defp load_filtered_tasks(socket) do
    scope = socket.assigns.current_scope

    due_from = parse_date_struct(socket.assigns.due_from)
    due_to = parse_date_struct(socket.assigns.due_to)

    opts = [
      search: socket.assigns.search,
      archive_filter: socket.assigns.archive_filter,
      status: socket.assigns.statuses,
      priority: socket.assigns.priorities,
      due_from: due_from,
      due_to: due_to,
      overdue: socket.assigns.overdue,
      sort_by: socket.assigns.sort_by,
      sort_dir: socket.assigns.sort_dir,
      page: socket.assigns.page,
      per_page: @per_page
    ]

    {tasks, total} = Tasks.list_tasks(scope, opts)

    tasks =
      tasks
      |> Enum.map(&Map.merge(&1, %{depth: 0, has_children?: false, tree_enter?: false}))
      |> then(fn rows ->
        case attach_contact_avatars(scope, rows) do
          {:ok, rows} -> rows
          _ -> rows
        end
      end)

    socket
    |> assign(:loading, false)
    |> assign(:total, total)
    |> stream(:tasks, tasks, reset: true)
  end

  defp apply_action(socket, :new, params) do
    parent_task_id = parse_id(Map.get(params, "parent_id"))

    # The task form needs these options on its first render. Loading them here
    # prevents LiveSelect from briefly receiving an empty option list and
    # falling back to displaying the numeric task type ID.
    socket = ensure_task_types_loaded(socket)

    assign(socket,
      page_title: gettext("Tasks"),
      task: task_from_params(params, parent_task_id),
      parent_task_id: parent_task_id
    )
  end

  defp apply_action(socket, :detail, %{"id" => id}) do
    assign(socket,
      page_title: gettext("Tasks"),
      task: nil,
      parent_task_id: nil,
      drawer_task_id: parse_id(id),
      drawer_refresh: socket.assigns.drawer_refresh + 1
    )
  end

  defp apply_action(socket, :index, _params) do
    assign(socket,
      page_title: gettext("Tasks"),
      task: nil,
      parent_task_id: nil,
      drawer_task_id: nil
    )
  end

  defp task_from_params(params, parent_task_id) do
    %Task{
      parent_task_id: parent_task_id,
      due_date: default_due_date(),
      title: Map.get(params, "title"),
      source_thread_id: parse_id(Map.get(params, "source_thread_id")),
      source_email_id: parse_id(Map.get(params, "source_email_id")),
      contact_id: parse_id(Map.get(params, "contact_id")),
      company_id: parse_id(Map.get(params, "company_id")),
      deal_id: parse_id(Map.get(params, "deal_id"))
    }
  end

  defp ensure_task_types_loaded(%{assigns: %{task_types: [_ | _]}} = socket), do: socket

  defp ensure_task_types_loaded(socket) do
    case Tasks.list_task_types(socket.assigns.current_scope) do
      {:ok, task_types} -> assign(socket, :task_types, task_types)
      {:error, _reason} -> socket
    end
  end

  @impl true
  def handle_info(:load_task_tree, socket) do
    if socket.assigns.filter_mode do
      {:noreply, socket}
    else
      {:noreply, reload_tree(socket)}
    end
  end

  def handle_info({:expand_task, task_id}, socket) do
    socket =
      if MapSet.member?(socket.assigns.expanded_task_ids, task_id) do
        expand_task(socket, task_id)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({DrawerComponent, :reload_tree}, socket) do
    {:noreply, refresh_list(socket)}
  end

  def handle_info({DrawerComponent, {:updated, field}}, socket) do
    {:noreply, socket |> put_task_update_flash(field) |> refresh_list()}
  end

  def handle_info(
        {KonevoWeb.TasksLive.FormComponent, {:saved, _task, dependency_result}},
        socket
      ) do
    socket =
      socket
      |> put_save_flash(dependency_result)
      |> push_patch(to: ~p"/tasks")
      |> refresh_list()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    task_id = parse_id(id)

    socket =
      if MapSet.member?(socket.assigns.expanded_task_ids, task_id) do
        collapse_task(socket, task_id)
      else
        start_expand_task(socket, task_id)
      end

    {:noreply, socket}
  end

  def handle_event("complete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    task = Tasks.get_task!(scope, id)

    case Tasks.complete_task(scope, task) do
      {:ok, _task} ->
        {:noreply, socket |> put_flash(:success, gettext("Task completed")) |> refresh_list()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this task"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, task_rule_error(reason))}
    end
  end

  def handle_event("update_status", %{"id" => id, "status" => status}, socket) do
    scope = socket.assigns.current_scope
    task = Tasks.get_task!(scope, id)

    case Tasks.update_task(scope, task, %{status: status}) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_task_update_flash(:status)
         |> refresh_list()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this task"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, task_rule_error(reason))}
    end
  end

  def handle_event("update_priority", %{"id" => id, "priority" => priority}, socket) do
    scope = socket.assigns.current_scope
    task = Tasks.get_task!(scope, id)

    case Tasks.update_task(scope, task, %{priority: priority}) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_task_update_flash(:priority)
         |> refresh_list()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this task"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to update priority"))}
    end
  end

  def handle_event("delete", %{"id" => id} = params, socket) do
    has_children = Map.get(params, "has_children", "false")

    {:noreply,
     socket
     |> assign(:confirm_delete_task_id, id)
     |> assign(:confirm_delete_has_children, has_children == "true")}
  end

  def handle_event("confirm_delete", _params, socket) do
    scope = socket.assigns.current_scope
    id = socket.assigns.confirm_delete_task_id
    task = Tasks.get_task!(scope, id)

    case Tasks.delete_task(scope, task) do
      {:ok, _task} ->
        expanded_task_ids = MapSet.delete(socket.assigns.expanded_task_ids, task.id)

        {:noreply,
         socket
         |> assign(:confirm_delete_task_id, nil)
         |> assign(:expanded_task_ids, expanded_task_ids)
         |> put_flash(:success, gettext("Task deleted"))
         |> refresh_list()}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> assign(:confirm_delete_task_id, nil)
         |> put_flash(:error, gettext("You cannot delete this task"))}

      {:error, :has_contact_or_deal} ->
        {:noreply,
         socket
         |> assign(:confirm_delete_task_id, nil)
         |> put_flash(
           :error,
           gettext("This task cannot be deleted because it is linked to a contact or deal")
         )}

      {:error, :has_dependents} ->
        {:noreply,
         socket
         |> assign(:confirm_delete_task_id, nil)
         |> put_flash(
           :error,
           gettext("This task cannot be deleted because other tasks depend on it")
         )}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete_task_id, nil)}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: build_url(socket, %{search: q, page: 1}), replace: true)}
  end

  def handle_event("clear_search", _, socket) do
    {:noreply, push_patch(socket, to: build_url(socket, %{search: "", page: 1}), replace: true)}
  end

  def handle_event("set_archive_filter", %{"filter" => filter}, socket) do
    archive_filter = parse_archive_filter(filter)

    {:noreply,
     push_patch(socket, to: build_url(socket, %{archive_filter: archive_filter, page: 1}))}
  end

  def handle_event("archive", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    task = Tasks.get_task!(scope, id)

    case Tasks.archive_task(scope, task) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:success, gettext("Task archived"))
         |> refresh_list()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Not allowed"))}
    end
  end

  def handle_event("restore", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    task = Tasks.get_task!(scope, id)

    case Tasks.restore_task(scope, task) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:success, gettext("Task restored"))
         |> refresh_list()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Not allowed"))}
    end
  end

  def handle_event("toggle_status", %{"status" => status_str}, socket) do
    status = String.to_existing_atom(status_str)
    current = socket.assigns.statuses

    new_statuses =
      if status in current,
        do: List.delete(current, status),
        else: [status | current]

    {:noreply, push_patch(socket, to: build_url(socket, %{statuses: new_statuses, page: 1}))}
  end

  def handle_event("toggle_all_statuses", _, socket) do
    new_statuses =
      if length(socket.assigns.statuses) == length(@all_statuses),
        do: [],
        else: @all_statuses

    {:noreply, push_patch(socket, to: build_url(socket, %{statuses: new_statuses, page: 1}))}
  end

  def handle_event("toggle_priority", %{"priority" => p_str}, socket) do
    priority = String.to_existing_atom(p_str)
    current = socket.assigns.priorities

    new_priorities =
      if priority in current,
        do: List.delete(current, priority),
        else: [priority | current]

    {:noreply, push_patch(socket, to: build_url(socket, %{priorities: new_priorities, page: 1}))}
  end

  def handle_event("toggle_all_priorities", _, socket) do
    new_priorities =
      if length(socket.assigns.priorities) == length(@all_priorities),
        do: [],
        else: @all_priorities

    {:noreply, push_patch(socket, to: build_url(socket, %{priorities: new_priorities, page: 1}))}
  end

  def handle_event("toggle_overdue", _, socket) do
    {:noreply,
     push_patch(socket, to: build_url(socket, %{overdue: !socket.assigns.overdue, page: 1}))}
  end

  def handle_event("filter_date_range", %{"from" => from, "to" => to}, socket) do
    from = parse_date_param(from)
    to = parse_date_param(to)

    {:noreply, push_patch(socket, to: build_url(socket, %{due_from: from, due_to: to, page: 1}))}
  end

  def handle_event("clear_filters", _, socket) do
    socket =
      socket
      |> push_patch(
        to:
          build_url(socket, %{
            search: "",
            archive_filter: :active,
            statuses: [],
            priorities: [],
            due_from: "",
            due_to: "",
            overdue: false,
            page: 1
          })
      )
      |> push_event("date_range:clear", %{})

    {:noreply, socket}
  end

  def handle_event("sort", %{"by" => by}, socket) do
    sort_by = parse_sort_by(by)

    sort_dir =
      if socket.assigns.sort_by == sort_by do
        if socket.assigns.sort_dir == :asc, do: :desc, else: :asc
      else
        :asc
      end

    {:noreply,
     push_patch(socket, to: build_url(socket, %{sort_by: sort_by, sort_dir: sort_dir, page: 1}))}
  end

  def handle_event("page", %{"n" => n_str}, socket) do
    case Integer.parse(n_str) do
      {n, ""} when n > 0 ->
        {:noreply, push_patch(socket, to: build_url(socket, %{page: n}))}

      _ ->
        {:noreply, socket}
    end
  end

  defp refresh_list(socket) do
    if socket.assigns.filter_mode do
      load_filtered_tasks(socket)
    else
      reload_tree(socket)
    end
  end

  defp build_url(socket, overrides) do
    search = Map.get(overrides, :search, socket.assigns.search)
    archive_filter = Map.get(overrides, :archive_filter, socket.assigns.archive_filter)
    statuses = Map.get(overrides, :statuses, socket.assigns.statuses)
    priorities = Map.get(overrides, :priorities, socket.assigns.priorities)
    due_from = Map.get(overrides, :due_from, socket.assigns.due_from)
    due_to = Map.get(overrides, :due_to, socket.assigns.due_to)
    overdue = Map.get(overrides, :overdue, socket.assigns.overdue)
    sort_by = Map.get(overrides, :sort_by, socket.assigns.sort_by)
    sort_dir = Map.get(overrides, :sort_dir, socket.assigns.sort_dir)
    page = Map.get(overrides, :page, socket.assigns.page)

    params =
      []
      |> push_url_param("search", search, "")
      |> push_url_param("archived", archive_filter_param(archive_filter), "active")
      |> push_url_param("statuses", Enum.join(statuses, ","), "")
      |> push_url_param("priorities", Enum.join(priorities, ","), "")
      |> push_url_param("due_from", due_from, "")
      |> push_url_param("due_to", due_to, "")
      |> push_url_param("overdue", to_string(overdue), "false")
      |> push_url_param("sort_by", to_string(sort_by), "due_date")
      |> push_url_param("sort_dir", to_string(sort_dir), "asc")
      |> push_url_param("page", to_string(page), "1")
      |> Map.new()

    if map_size(params) == 0, do: ~p"/tasks", else: ~p"/tasks?#{params}"
  end

  defp push_url_param(list, _key, default, default), do: list
  defp push_url_param(list, key, value, _default), do: [{key, value} | list]

  defp archive_filter_param(:archived), do: "archived"
  defp archive_filter_param(:all), do: "all"
  defp archive_filter_param(_), do: "active"

  defp archive_filter_options do
    [
      {gettext("Active"), "active", "icon-[tabler--circle-check]"},
      {gettext("Archived"), "archived", "icon-[tabler--archive]"},
      {gettext("All"), "all", "icon-[tabler--stack-2]"}
    ]
  end

  defp parse_date_struct(""), do: nil

  defp parse_date_struct(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp reload_tree(socket) do
    scope = socket.assigns.current_scope

    with {:ok, task_types} <- Tasks.list_task_types(scope),
         {:ok, rows} <-
           visible_tree_rows(
             scope,
             socket.assigns.expanded_task_ids,
             socket.assigns.archive_filter
           ),
         {:ok, rows} <- attach_contact_avatars(scope, rows),
         {:ok, task_options} <- Tasks.list_task_options(scope) do
      socket
      |> assign(:loading, false)
      |> assign(:task_rows, rows)
      |> assign(:task_types, task_types)
      |> assign(:task_options, task_options)
      |> stream(:tasks, rows, reset: true)
    else
      {:error, :unauthorized} ->
        socket
        |> assign(:loading, false)
        |> put_flash(:error, gettext("You cannot view tasks"))

      _other ->
        socket
        |> assign(:loading, false)
        |> put_flash(:error, gettext("Failed to load tasks"))
    end
  end

  defp collapse_task(socket, task_id) do
    ids = [task_id | loaded_descendant_ids(socket.assigns.task_rows, task_id)]
    descendant_ids = MapSet.new(tl(ids))
    collapsed_task = Enum.find(socket.assigns.task_rows, &(&1.id == task_id))
    removed_rows = Enum.filter(socket.assigns.task_rows, &MapSet.member?(descendant_ids, &1.id))
    rows = Enum.reject(socket.assigns.task_rows, &MapSet.member?(descendant_ids, &1.id))
    expanded_task_ids = Enum.reduce(ids, socket.assigns.expanded_task_ids, &MapSet.delete(&2, &1))

    socket
    |> assign(:expanded_task_ids, expanded_task_ids)
    |> assign(:task_rows, rows)
    |> maybe_stream_task(collapsed_task)
    |> maybe_delete_loading_children_row(collapsed_task)
    |> delete_task_rows(removed_rows)
  end

  defp maybe_stream_task(socket, nil), do: socket
  defp maybe_stream_task(socket, task), do: stream_insert(socket, :tasks, task)

  defp maybe_delete_loading_children_row(socket, nil), do: socket

  defp maybe_delete_loading_children_row(socket, task) do
    Enum.reduce(loading_children_rows(task), socket, &stream_delete(&2, :tasks, &1))
  end

  defp delete_task_rows(socket, rows) do
    Enum.reduce(rows, socket, &stream_delete(&2, :tasks, &1))
  end

  defp start_expand_task(socket, task_id) do
    case Enum.find(socket.assigns.task_rows, &(&1.id == task_id)) do
      nil ->
        socket

      parent ->
        send(self(), {:expand_task, task_id})

        skeleton_rows = loading_children_rows(parent)
        rows_with_skeletons = insert_after(socket.assigns.task_rows, task_id, skeleton_rows)

        socket
        |> assign(:expanded_task_ids, MapSet.put(socket.assigns.expanded_task_ids, task_id))
        |> stream(:tasks, rows_with_skeletons, reset: true)
    end
  end

  defp expand_task(socket, task_id) do
    scope = socket.assigns.current_scope
    parent = Enum.find(socket.assigns.task_rows, &(&1.id == task_id))

    with %{depth: depth} <- parent,
         {:ok, children} <-
           Tasks.list_tree_tasks(scope,
             parent_task_id: task_id,
             depth: depth + 1,
             archive_filter: socket.assigns.archive_filter
           ),
         {:ok, children} <- attach_contact_avatars(scope, children) do
      descendant_ids = socket.assigns.task_rows |> loaded_descendant_ids(task_id) |> MapSet.new()
      base_rows = Enum.reject(socket.assigns.task_rows, &MapSet.member?(descendant_ids, &1.id))

      rows = insert_after(base_rows, task_id, children)

      parent_idx = Enum.find_index(base_rows, &(&1.id == task_id)) || 0
      insert_at = parent_idx + 1

      socket
      |> assign(:expanded_task_ids, MapSet.put(socket.assigns.expanded_task_ids, task_id))
      |> assign(:task_rows, rows)
      |> maybe_delete_loading_children_row(parent)
      |> insert_child_task_rows(children, insert_at)
    else
      {:error, :unauthorized} ->
        socket
        |> assign(:expanded_task_ids, MapSet.delete(socket.assigns.expanded_task_ids, task_id))
        |> maybe_delete_loading_children_row(parent)
        |> put_flash(:error, gettext("You cannot view tasks"))

      _ ->
        socket
        |> assign(:expanded_task_ids, MapSet.delete(socket.assigns.expanded_task_ids, task_id))
        |> maybe_delete_loading_children_row(parent)
    end
  end

  defp mark_tree_enter(row), do: Map.put(row, :tree_enter?, true)

  defp insert_child_task_rows(socket, children, insert_at) do
    children
    |> Enum.with_index(insert_at)
    |> Enum.reduce(socket, fn {child, at}, socket ->
      stream_insert(socket, :tasks, mark_tree_enter(child), at: at)
    end)
  end

  defp loading_children_rows(parent) do
    count = max(Map.get(parent, :child_count, 1), 1)

    Enum.map(0..(count - 1), fn i ->
      %{
        id: "loading-children-#{parent.id}-#{i}",
        depth: parent.depth + 1,
        loading_children_for: parent.id,
        skeleton_index: i
      }
    end)
  end

  defp loading_children_row?(%{loading_children_for: _id}), do: true
  defp loading_children_row?(_task), do: false

  defp insert_after(rows, task_id, new_rows) do
    Enum.flat_map(rows, fn row ->
      if row.id == task_id, do: [row | new_rows], else: [row]
    end)
  end

  defp visible_tree_rows(scope, expanded_task_ids, archive_filter) do
    with {:ok, roots} <-
           Tasks.list_tree_tasks(scope,
             parent_task_id: nil,
             depth: 0,
             archive_filter: archive_filter
           ) do
      rows =
        Enum.flat_map(roots, fn task ->
          [task | expanded_children(scope, task, expanded_task_ids, archive_filter)]
        end)

      {:ok, rows}
    end
  end

  defp expanded_children(scope, task, expanded_task_ids, archive_filter) do
    if MapSet.member?(expanded_task_ids, task.id) do
      case Tasks.list_tree_tasks(scope,
             parent_task_id: task.id,
             depth: task.depth + 1,
             archive_filter: archive_filter
           ) do
        {:ok, children} ->
          Enum.flat_map(children, fn child ->
            [child | expanded_children(scope, child, expanded_task_ids, archive_filter)]
          end)

        {:error, _} ->
          []
      end
    else
      []
    end
  end

  defp loaded_descendant_ids(rows, task_id) do
    descendants_by_parent =
      Enum.reduce(rows, %{}, fn row, acc ->
        if row.parent_task_id do
          Map.update(acc, row.parent_task_id, [row.id], &[row.id | &1])
        else
          acc
        end
      end)

    collect_descendants(descendants_by_parent, [task_id], MapSet.new())
    |> MapSet.to_list()
  end

  defp collect_descendants(_descendants_by_parent, [], acc), do: acc

  defp collect_descendants(descendants_by_parent, parent_ids, acc) do
    child_ids = Enum.flat_map(parent_ids, &Map.get(descendants_by_parent, &1, []))
    acc = Enum.reduce(child_ids, acc, &MapSet.put(&2, &1))
    collect_descendants(descendants_by_parent, child_ids, acc)
  end

  defp attach_contact_avatars(scope, rows) do
    contacts =
      rows
      |> Enum.map(& &1.contact)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.id)

    case Uploads.attach_contact_avatars(scope, contacts) do
      {:ok, contacts} ->
        contacts_by_id = Map.new(contacts, &{&1.id, &1})

        rows =
          Enum.map(rows, fn
            %{contact: %{id: id}} = row ->
              %{row | contact: Map.get(contacts_by_id, id, row.contact)}

            row ->
              row
          end)

        {:ok, rows}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_id(nil), do: nil
  defp parse_id(value) when is_integer(value), do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp default_due_date, do: DateTime.utc_now(:second) |> DateTime.add(86_400, :second)

  defp put_save_flash(socket, :ok), do: put_flash(socket, :success, gettext("Task created"))

  defp put_save_flash(socket, {:error, :dependency}) do
    put_flash(socket, :warning, gettext("Task created, but dependency could not be added"))
  end

  defp put_task_update_flash(socket, :description),
    do: put_flash(socket, :success, gettext("Notes saved"))

  defp put_task_update_flash(socket, :status),
    do: put_flash(socket, :success, gettext("Task status updated"))

  defp put_task_update_flash(socket, :priority),
    do: put_flash(socket, :success, gettext("Task priority updated"))

  defp put_task_update_flash(socket, :due_date),
    do: put_flash(socket, :success, gettext("Task due date updated"))

  defp put_task_update_flash(socket, _field),
    do: put_flash(socket, :success, gettext("Task updated"))

  defp task_rule_error(:task_has_open_dependencies),
    do: gettext("This task is blocked by unfinished dependencies")

  defp task_rule_error(:task_has_open_children),
    do: gettext("Complete or cancel child tasks before completing this task")

  defp task_rule_error(:parent_status_is_derived),
    do: gettext("This status is derived from child tasks and cannot be changed directly")

  defp task_rule_error(:dependency_cycle), do: gettext("That dependency would create a cycle")
  defp task_rule_error(:invalid_dependency), do: gettext("A task cannot depend on itself")
  defp task_rule_error(_reason), do: gettext("Failed to update status")

  @impl true
  def render(assigns) do
    total_pages = total_pages(assigns.total)

    assigns =
      assigns
      |> assign(:total_pages, total_pages)
      |> assign(
        :page_from,
        if(assigns.total > 0, do: (assigns.page - 1) * @per_page + 1, else: 0)
      )
      |> assign(:page_to, min(assigns.page * @per_page, assigns.total))
      |> assign(:page_numbers, page_display(assigns.page, total_pages))
      |> assign(:all_statuses, @all_statuses)
      |> assign(:all_priorities, @all_priorities)
      |> assign(
        :has_active_filters,
        filter_mode?(
          assigns.search,
          assigns.archive_filter,
          assigns.statuses,
          assigns.priorities,
          assigns.due_from,
          assigns.due_to,
          assigns.overdue
        )
      )
      |> assign(
        :filter_controls_active?,
        assigns.archive_filter != :active or assigns.statuses != [] or assigns.priorities != [] or
          assigns.due_from != "" or assigns.due_to != "" or assigns.overdue
      )
      |> assign(
        :filter_controls_count,
        if(assigns.archive_filter != :active, do: 1, else: 0) + length(assigns.statuses) +
          length(assigns.priorities) + if(assigns.due_from != "", do: 1, else: 0) +
          if(assigns.due_to != "", do: 1, else: 0) + if(assigns.overdue, do: 1, else: 0)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.page title={@page_title}>
        <:actions>
          <.button patch={~p"/tasks/new"} id="new-task-button" class="btn btn-primary btn-sm gap-1.5">
            <.icon name="icon-[tabler--plus]" class="size-4" /> {gettext("New Task")}
          </.button>
        </:actions>
        <%!-- Toolbar --%>
        <div class="mb-4 flex flex-wrap items-center gap-2">
          <%!-- Search --%>
          <div class="relative w-full shrink-0 sm:w-52">
            <span class="icon-[tabler--search] pointer-events-none absolute left-2.5 top-1/2 z-10 size-3.5 -translate-y-1/2 text-base-content/40" />
            <form phx-change="search" phx-submit="search" id="task-search-form">
              <input
                type="text"
                name="q"
                value={@search}
                placeholder={gettext("Search tasks...")}
                phx-debounce="300"
                class={[
                  "input input-sm input-bordered w-full pl-8 pr-8 transition-colors",
                  @search != "" && "border-primary/60"
                ]}
                autocomplete="off"
              />
            </form>

            <button
              :if={@search != ""}
              phx-click="clear_search"
              type="button"
              aria-label={gettext("Clear search")}
              class="absolute right-2.5 top-1/2 -translate-y-1/2 text-base-content/40 hover:text-base-content transition-colors"
            >
              <span class="icon-[tabler--x] size-3.5" />
            </button>
          </div>

          <div class="hidden sm:block">
            <.archive_filter_dropdown
              id="tasks-archive-filter"
              selected={@archive_filter}
              options={archive_filter_options()}
            />
          </div>
          <%!-- Filter dropdowns --%>
          <%!-- Mobile filter toggle --%>
          <div class="flex items-center gap-2 sm:hidden">
            <button
              type="button"
              class={[
                "btn btn-sm gap-1.5 border select-none",
                if(@filter_controls_active?,
                  do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                  else:
                    "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                )
              ]}
              phx-click={
                JS.toggle(
                  to: "#tasks-filter-panel",
                  display: "flex",
                  in:
                    {"transition ease-out duration-200", "opacity-0 -translate-y-1",
                     "opacity-100 translate-y-0"},
                  out:
                    {"transition ease-in duration-150", "opacity-100 translate-y-0",
                     "opacity-0 -translate-y-1"}
                )
                |> JS.toggle_class("rotate-180", to: "#tasks-filter-chevron")
              }
            >
              <span class="icon-[tabler--adjustments-horizontal] size-3.5" />
              {gettext("Filters")}
              <span
                :if={@filter_controls_active?}
                class="flex size-4 items-center justify-center rounded-full bg-primary text-[10px] font-bold text-primary-content"
              >
                {@filter_controls_count}
              </span>
              <span
                id="tasks-filter-chevron"
                class="icon-[tabler--chevron-down] size-3.5 opacity-50 transition-transform duration-200"
              />
            </button>
            <button
              :if={@filter_controls_active?}
              id="tasks-clear-filters-mobile"
              phx-click="clear_filters"
              type="button"
              aria-label={gettext("Clear filters")}
              class="btn btn-sm btn-square border border-base-content/20 bg-base-100 text-base-content/60 transition-all hover:border-base-content/30 hover:text-base-content"
            >
              <.icon name="icon-[tabler--x]" class="size-3.5" />
            </button>
          </div>
          <div
            id="tasks-filter-panel"
            class="hidden w-full flex-wrap items-center gap-2 rounded-xl border border-secondary/35 bg-secondary/10 p-3 sm:w-auto sm:rounded-none sm:border-0 sm:bg-transparent sm:p-0 sm:flex"
          >
            <div class="sm:hidden">
              <.archive_filter_dropdown
                id="tasks-archive-filter-mobile"
                selected={@archive_filter}
                options={archive_filter_options()}
              />
            </div>

            <%!-- Status filter --%>
            <div class="relative" id="task-status-filter" phx-hook="FilterPanel">
              <button
                type="button"
                data-toggle
                class={[
                  "btn btn-sm gap-1.5 border select-none transition-all",
                  if(@statuses != [],
                    do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                    else:
                      "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                  )
                ]}
              >
                <span class="icon-[tabler--filter] size-3.5" /> {gettext("Status")}
                <span
                  :if={@statuses != []}
                  class="flex size-4 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-content"
                >
                  {length(@statuses)}
                </span>
                <span class="icon-[tabler--chevron-down] size-3.5 opacity-50" />
              </button>
              <div
                data-panel
                class="row-menu-closed z-30 min-w-52 overflow-hidden rounded-xl border border-base-content/20 bg-base-100 shadow-xl"
              >
                <label class="flex w-full cursor-pointer select-none items-center gap-3 px-3 py-2.5 hover:bg-base-200 transition-colors">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-xs checkbox-primary shrink-0"
                    checked={length(@statuses) == length(@all_statuses)}
                    phx-click="toggle_all_statuses"
                    data-select-all
                  /> <span class="text-sm font-semibold">{gettext("Select all")}</span>
                </label>
                <div class="mx-2 border-t border-base-content/10" />
                <div class="p-1">
                  <label
                    :for={status <- @all_statuses}
                    class="flex w-full cursor-pointer select-none items-center gap-3 rounded-lg px-3 py-2 hover:bg-base-200 transition-colors"
                  >
                    <input
                      type="checkbox"
                      class="checkbox checkbox-xs checkbox-primary shrink-0"
                      checked={status in @statuses}
                      phx-click="toggle_status"
                      phx-value-status={status}
                      data-select-option
                    />
                    <span class={["size-2 rounded-full shrink-0", task_status_dot_class(status)]} />
                    <span class="text-sm">{task_status_label(status)}</span>
                  </label>
                </div>
              </div>
            </div>
            <%!-- Priority filter --%>
            <div class="relative" id="task-priority-filter" phx-hook="FilterPanel">
              <button
                type="button"
                data-toggle
                class={[
                  "btn btn-sm gap-1.5 border select-none transition-all",
                  if(@priorities != [],
                    do: "border-primary/50 bg-primary/10 text-primary hover:bg-primary/15",
                    else:
                      "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                  )
                ]}
              >
                <span class="icon-[tabler--flag] size-3.5" /> {gettext("Priority")}
                <span
                  :if={@priorities != []}
                  class="flex size-4 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-content"
                >
                  {length(@priorities)}
                </span>
                <span class="icon-[tabler--chevron-down] size-3.5 opacity-50" />
              </button>
              <div
                data-panel
                class="row-menu-closed z-30 min-w-48 overflow-hidden rounded-xl border border-base-content/20 bg-base-100 shadow-xl"
              >
                <label class="flex w-full cursor-pointer select-none items-center gap-3 px-3 py-2.5 hover:bg-base-200 transition-colors">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-xs checkbox-primary shrink-0"
                    checked={length(@priorities) == length(@all_priorities)}
                    phx-click="toggle_all_priorities"
                    data-select-all
                  /> <span class="text-sm font-semibold">{gettext("Select all")}</span>
                </label>
                <div class="mx-2 border-t border-base-content/10" />
                <div class="p-1">
                  <label
                    :for={priority <- @all_priorities}
                    class="flex w-full cursor-pointer select-none items-center gap-3 rounded-lg px-3 py-2 hover:bg-base-200 transition-colors"
                  >
                    <input
                      type="checkbox"
                      class="checkbox checkbox-xs checkbox-primary shrink-0"
                      checked={priority in @priorities}
                      phx-click="toggle_priority"
                      phx-value-priority={priority}
                      data-select-option
                    />
                    <span
                      class="icon-[tabler--flag-filled] size-3.5 shrink-0"
                      style={"color: #{priority_color(priority)}"}
                    /> <span class="text-sm">{Phoenix.Naming.humanize(priority)}</span>
                  </label>
                </div>
              </div>
            </div>
            <%!-- Due date range --%>
            <.date_range_picker
              id="task-due-date-filter"
              created_from={@due_from}
              created_to={@due_to}
            /> <%!-- Overdue quick-filter --%>
            <button
              type="button"
              phx-click="toggle_overdue"
              class={[
                "btn btn-sm gap-1.5 border select-none transition-all",
                if(@overdue,
                  do: "border-error/50 bg-error/10 text-error hover:bg-error/15",
                  else:
                    "border-base-content/20 bg-base-100 text-base-content hover:border-base-content/30"
                )
              ]}
            >
              <span class="icon-[tabler--clock-exclamation] size-3.5" /> {gettext("Overdue")}
            </button>
            <%!-- Clear all filters --%>
            <div
              :if={@has_active_filters}
              class="hidden border-l border-base-content/15 pl-2 sm:block"
            >
              <button
                id="tasks-clear-filters"
                phx-click="clear_filters"
                type="button"
                class="btn btn-sm gap-1.5 border border-base-content/20 bg-base-100 text-base-content/60 transition-all hover:border-base-content/30 hover:text-base-content"
              >
                <.icon name="icon-[tabler--x]" class="size-3" /> {gettext("Clear filters")}
              </button>
            </div>
          </div>
          <%!-- Filter mode badge --%>
          <div
            :if={@filter_mode}
            class="ml-auto flex items-center gap-1.5 text-xs text-base-content/40"
          >
            <span class="icon-[tabler--list] size-3.5" /> {gettext("Filtered view")}
          </div>
        </div>

        <div
          :if={@loading}
          id="tasks-loading"
          class="tasks-mobile-container overflow-x-auto rounded-xl border border-base-content/20 bg-base-100"
        >
          <table class="tasks-responsive-table table w-full min-w-6xl table-fixed">
            <.tasks_table_header filter_mode={@filter_mode} sort_by={@sort_by} sort_dir={@sort_dir} />
            <tbody class="divide-y divide-base-content/8">
              <tr
                :for={row <- 1..7}
                id={"task-skeleton-#{row}"}
                class="task-mobile-skeleton divide-x divide-base-content/8"
              >
                <td class="px-4 py-3"><div class="skeleton h-4 w-56 rounded-md" /></td>

                <td class="px-4 py-3">
                  <div class="flex items-center gap-2.5">
                    <div class="skeleton size-8 rounded-full" />
                    <div class="skeleton h-4 w-28 rounded-md" />
                  </div>
                </td>

                <td class="px-4 py-3"><div class="skeleton h-6 w-14 rounded-full" /></td>

                <td class="px-4 py-3"><div class="skeleton h-5 w-16 rounded-full" /></td>

                <td class="px-4 py-3"><div class="skeleton h-5 w-16 rounded-full" /></td>

                <td class="px-4 py-3"><div class="skeleton h-4 w-24 rounded-md" /></td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          :if={!@loading}
          id="tasks-table"
          phx-hook="NameTip"
          class="tasks-mobile-container overflow-x-auto rounded-xl border border-base-content/20 bg-base-100 shadow-sm"
        >
          <table class="tasks-responsive-table table w-full min-w-6xl table-fixed">
            <.tasks_table_header filter_mode={@filter_mode} sort_by={@sort_by} sort_dir={@sort_dir} />
            <tbody id="tasks" phx-update="stream" class="divide-y divide-base-content/8">
              <tr id="tasks-empty" class="hidden only:table-row">
                <td colspan="6" class="px-4 py-16 text-center">
                  <.icon
                    name="icon-[tabler--clipboard-list]"
                    class="mx-auto mb-3 size-10 text-base-content/20"
                  />
                  <p class="text-sm font-medium text-base-content/50">
                    <%= if @filter_mode do %>
                      {gettext("No tasks match your filters.")}
                    <% else %>
                      {gettext("No tasks yet. Add your first task.")}
                    <% end %>
                  </p>

                  <p :if={@filter_mode} class="mt-1 text-xs text-base-content/30">
                    {gettext("Try adjusting your search or filters.")}
                  </p>
                </td>
              </tr>

              <tr
                :for={{id, task} <- @streams.tasks}
                id={id}
                phx-mounted={task_tree_enter(task)}
                phx-remove={
                  unless loading_children_row?(task) do
                    JS.transition(
                      {"task-tree-row-leave", "task-tree-row-leave-start", "task-tree-row-leave-end"},
                      time: 90
                    )
                  end
                }
                class={[
                  "task-tree-row task-mobile-card group divide-x divide-base-content/8 transition-colors hover:bg-base-200/40",
                  loading_children_row?(task) && "task-mobile-skeleton"
                ]}
              >
                <%= if loading_children_row?(task) do %>
                  <td class="px-4 py-3">
                    <div style={"padding-left: #{task.depth * 1.25}rem"}>
                      <div class={[
                        "skeleton h-4 rounded-md",
                        case rem(Map.get(task, :skeleton_index, 0), 3) do
                          0 -> "w-56"
                          1 -> "w-44"
                          _ -> "w-64"
                        end
                      ]} />
                    </div>
                  </td>

                  <td class="px-4 py-3">
                    <div class="flex items-center gap-2.5">
                      <div class="skeleton size-8 rounded-full" />
                      <div class="skeleton h-4 w-28 rounded-md" />
                    </div>
                  </td>

                  <td class="px-4 py-3"><div class="skeleton h-6 w-14 rounded-full" /></td>

                  <td class="px-4 py-3"><div class="skeleton h-5 w-16 rounded-full" /></td>

                  <td class="px-4 py-3"><div class="skeleton h-5 w-16 rounded-full" /></td>

                  <td class="px-4 py-3"><div class="skeleton h-4 w-24 rounded-md" /></td>
                <% else %>
                  <td class="task-mobile-card-title relative overflow-hidden px-3 py-2.5">
                    <div
                      class="task-mobile-title-content flex min-w-0 items-center gap-2"
                      style={"--task-depth: #{task.depth}; padding-left: calc(var(--task-depth) * 1.25rem)"}
                    >
                      <button
                        :if={task.has_children?}
                        type="button"
                        phx-click={
                          JS.push("toggle", value: %{id: task.id})
                          |> JS.toggle_class("-rotate-90", to: "#chevron-#{task.id}")
                        }
                        aria-expanded={MapSet.member?(@expanded_task_ids, task.id)}
                        class={[
                          "toggle-btn flex size-6 shrink-0 items-center justify-center rounded-md transition-all duration-150 ease-out",
                          if(MapSet.member?(@expanded_task_ids, task.id),
                            do: "bg-primary/10 text-primary shadow-sm ring-1 ring-primary/15",
                            else:
                              "text-base-content/50 hover:bg-base-content/10 hover:text-base-content"
                          )
                        ]}
                        aria-label={gettext("Toggle children")}
                      >
                        <.icon
                          id={"chevron-#{task.id}"}
                          name="icon-[tabler--chevron-down]"
                          class={[
                            "size-4 transition-transform duration-200 ease-out",
                            !MapSet.member?(@expanded_task_ids, task.id) && "-rotate-90"
                          ]}
                        /> <span class="loading-spinner loading loading-xs hidden" />
                      </button>
                      <span :if={!task.has_children?} class="size-6 shrink-0" />
                      <div
                        class="flex size-7 shrink-0 items-center justify-center rounded-lg border"
                        style={task_type_chip_style(task)}
                      >
                        <.icon name={task_type_icon(task)} class="size-4.5 shrink-0" />
                      </div>

                      <div class="min-w-0 flex-1">
                        <.link
                          patch={~p"/tasks/#{task.id}"}
                          data-full-name={task.title}
                          data-task-link
                          phx-click={
                            JS.set_attribute({"data-pre-open", "true"}, to: "#task-drawer")
                            |> JS.set_attribute({"data-pre-open", "true"},
                              to: "#task-drawer-backdrop"
                            )
                          }
                          class="block w-full truncate text-left text-sm font-semibold text-base-content underline-offset-2 hover:underline hover:decoration-base-content/40"
                        >
                          {task.title}
                        </.link>
                        <.task_signals task={task} />
                      </div>

                      <div
                        id={"task-row-menu-#{task.id}"}
                        phx-hook="RowMenu"
                        class="relative shrink-0"
                      >
                        <button
                          type="button"
                          data-toggle
                          class="flex size-7 cursor-pointer items-center justify-center rounded-md text-base-content/40 transition-colors hover:bg-base-content/10 hover:text-base-content"
                          aria-label={gettext("Actions")}
                        >
                          <.icon name="icon-[tabler--dots-vertical]" class="size-4" />
                        </button>
                        <ul
                          data-panel
                          class="row-menu-closed z-50 w-44 overflow-hidden rounded-lg border border-base-content/15 bg-base-100 p-1 shadow-xl shadow-base-content/10"
                          role="menu"
                        >
                          <li>
                            <.link
                              patch={~p"/tasks/new/#{task.id}"}
                              class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-primary/10 hover:text-primary"
                            >
                              <.icon name="icon-[tabler--plus]" class="size-3.5" /> {gettext(
                                "Add child"
                              )}
                            </.link>
                          </li>

                          <li>
                            <button
                              type="button"
                              phx-click="complete"
                              phx-value-id={task.id}
                              disabled={task_status(task) == :done}
                              title={complete_action_title(task)}
                              class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-base-content/70 transition-colors hover:bg-success/10 hover:text-success disabled:pointer-events-none disabled:opacity-40"
                            >
                              <.icon name="icon-[tabler--check]" class="size-3.5" /> {gettext(
                                "Complete"
                              )}
                            </button>
                          </li>

                          <li>
                            <%= if is_nil(task.archived_at) do %>
                              <button
                                type="button"
                                phx-click="archive"
                                phx-value-id={task.id}
                                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-base-content/70 transition-colors hover:bg-warning/10 hover:text-warning"
                              >
                                <.icon name="icon-[tabler--archive]" class="size-3.5" />
                                {gettext("Archive")}
                              </button>
                            <% else %>
                              <button
                                type="button"
                                phx-click="restore"
                                phx-value-id={task.id}
                                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium text-base-content/70 transition-colors hover:bg-success/10 hover:text-success"
                              >
                                <.icon name="icon-[tabler--archive-off]" class="size-3.5" />
                                {gettext("Restore")}
                              </button>
                            <% end %>
                          </li>

                          <li>
                            <button
                              id={"tasks-delete-#{task.id}"}
                              type="button"
                              phx-click="delete"
                              phx-value-id={task.id}
                              phx-value-has_children={to_string(task.has_children?)}
                              class="danger-action flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium transition-colors"
                            >
                              <.icon name="icon-[tabler--trash]" class="size-3.5" /> {gettext(
                                "Delete"
                              )}
                            </button>
                          </li>
                        </ul>
                      </div>
                    </div>
                  </td>

                  <td class={[
                    "task-mobile-field task-mobile-contact px-3 py-2.5",
                    is_nil(task.contact) && "task-mobile-empty"
                  ]}>
                    <span class="task-mobile-field-label">{gettext("Contact")}</span>
                    <.task_contact_cell contact={task.contact} />
                  </td>

                  <td class={[
                    "task-mobile-field task-mobile-deal px-3 py-2.5",
                    is_nil(task.deal) && "task-mobile-empty"
                  ]}>
                    <span class="task-mobile-field-label">{gettext("Deal")}</span>
                    <.task_deal_cell deal={task.deal} />
                  </td>

                  <td class="task-mobile-field task-mobile-status px-3 py-2.5">
                    <span class="task-mobile-field-label">{gettext("Status")}</span>
                    <.status_pill
                      task_id={task.id}
                      status={task_status(task)}
                      readonly={task_status_derived?(task)}
                      readonly_reason={status_readonly_reason(task)}
                    />
                  </td>

                  <td class="task-mobile-field task-mobile-priority px-3 py-2.5">
                    <span class="task-mobile-field-label">{gettext("Priority")}</span>
                    <.priority_pill
                      task_id={task.id}
                      priority={task.priority}
                    />
                  </td>

                  <td class={[
                    "task-mobile-field task-mobile-due px-3 py-2.5 text-sm text-base-content/60",
                    is_nil(task.due_date) && "task-mobile-empty"
                  ]}>
                    <span class="task-mobile-field-label">{gettext("Due")}</span>
                    <span>{format_due_date(task.due_date)}</span>
                  </td>
                <% end %>
              </tr>
            </tbody>
          </table>
        </div>
        <%!-- Footer: count + pagination (filter mode only) --%>
        <div
          :if={@filter_mode and !@loading and @total > 0}
          id="tasks-footer"
          class="mt-6 flex flex-wrap items-center justify-between gap-3"
        >
          <p class="text-sm text-base-content/50">
            <%= if @total == 0 do %>
              {gettext("No tasks found")}
            <% else %>
              {gettext("Showing %{from}–%{to} of %{total}",
                from: @page_from,
                to: @page_to,
                total: @total
              )}
            <% end %>
          </p>

          <nav :if={@total_pages > 1} aria-label={gettext("Pagination")}>
            <ul class="flex items-center gap-0.5 rounded-xl border border-base-content/10 bg-base-100 p-1 shadow-sm">
              <li>
                <button
                  phx-click="page"
                  phx-value-n={@page - 1}
                  disabled={@page == 1}
                  class="flex h-8 w-8 items-center justify-center rounded-lg bg-base-content text-base-100 transition-all hover:opacity-80 disabled:pointer-events-none disabled:opacity-20"
                  aria-label={gettext("Previous page")}
                >
                  <span class="icon-[tabler--chevron-left] size-4" />
                </button>
              </li>

              <li :for={n <- @page_numbers}>
                <%= if n == :gap do %>
                  <span class="flex h-8 w-8 items-center justify-center text-sm text-base-content/30 select-none">
                    …
                  </span>
                <% else %>
                  <button
                    phx-click="page"
                    phx-value-n={n}
                    aria-current={if(n == @page, do: "page")}
                    class={[
                      "flex h-8 w-8 items-center justify-center rounded-lg text-sm font-medium transition-all select-none",
                      if(n == @page,
                        do: "bg-primary text-primary-content shadow-sm ring-1 ring-primary/30",
                        else: "text-base-content/60 hover:bg-primary/10 hover:text-primary"
                      )
                    ]}
                  >
                    {n}
                  </button>
                <% end %>
              </li>

              <li>
                <button
                  phx-click="page"
                  phx-value-n={@page + 1}
                  disabled={@page >= @total_pages}
                  class="flex h-8 w-8 items-center justify-center rounded-lg bg-base-content text-base-100 transition-all hover:opacity-80 disabled:pointer-events-none disabled:opacity-20"
                  aria-label={gettext("Next page")}
                >
                  <span class="icon-[tabler--chevron-right] size-4" />
                </button>
              </li>
            </ul>
          </nav>
        </div>
      </Layouts.page>

      <.modal
        :if={@live_action == :new}
        id="task-modal"
        show
        on_cancel={hide_modal("task-modal") |> JS.patch(~p"/tasks")}
      >
        <.live_component
          module={KonevoWeb.TasksLive.FormComponent}
          id="task-form-component"
          task={@task}
          current_scope={@current_scope}
          task_types={@task_types}
          task_options={@task_options}
          parent_task_id={@parent_task_id}
        />
      </.modal>
      <%!-- Task detail drawer --%>
      <.live_component
        module={DrawerComponent}
        id="task-drawer-component"
        task_id={@drawer_task_id}
        current_scope={@current_scope}
        open={@live_action == :detail}
        refresh={@drawer_refresh}
      />

      <%!-- Delete confirmation modal --%>
      <div
        :if={@confirm_delete_task_id}
        id="tasks-delete-confirmation"
        class="fixed inset-0 z-50 flex items-center justify-center"
      >
        <div class="absolute inset-0 bg-base-content/30 backdrop-blur-sm" phx-click="cancel_delete" />
        <div class="relative z-10 w-full max-w-sm rounded-2xl border border-base-content/10 bg-base-100 p-6 shadow-2xl">
          <div class="mb-4 flex size-11 items-center justify-center rounded-xl bg-error/10">
            <.icon name="icon-[tabler--trash]" class="size-5 text-error" />
          </div>
          <h3 class="mb-1.5 text-base font-semibold text-base-content">
            {gettext("Delete task?")}
          </h3>
          <p class="mb-6 text-sm text-base-content/60">
            <%= if @confirm_delete_has_children do %>
              {gettext(
                "This will permanently delete the task and all its subtasks. This action cannot be undone."
              )}
            <% else %>
              {gettext("This will permanently delete the task. This action cannot be undone.")}
            <% end %>
          </p>
          <div class="flex gap-2">
            <button
              id="tasks-cancel-delete"
              type="button"
              phx-click="cancel_delete"
              class="flex-1 rounded-xl border border-base-content/15 bg-base-200/60 px-4 py-2.5 text-sm font-medium text-base-content/70 transition-colors hover:bg-base-200"
            >
              {gettext("Cancel")}
            </button>
            <button
              id="tasks-confirm-delete"
              type="button"
              phx-click="confirm_delete"
              class="flex-1 rounded-xl bg-error px-4 py-2.5 text-sm font-semibold text-white transition-opacity hover:opacity-90"
            >
              {gettext("Delete")}
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Table header
  # ---------------------------------------------------------------------------

  defp task_tree_enter(task) do
    if Map.get(task, :tree_enter?, false) do
      JS.transition(
        {"task-tree-row-enter", "task-tree-row-enter-start", "task-tree-row-enter-end"},
        time: 180
      )
    end
  end

  attr :filter_mode, :boolean, default: false
  attr :sort_by, :atom, default: :due_date
  attr :sort_dir, :atom, default: :asc

  defp tasks_table_header(assigns) do
    ~H"""
    <colgroup>
      <col class="w-96" /> <col class="w-56" /> <col class="w-28" /> <col class="w-36" />
      <col class="w-36" /> <col class="w-36" />
    </colgroup>

    <thead>
      <tr class="divide-x divide-base-content/15 border-b border-secondary/35 bg-secondary/10">
        <%= if @filter_mode do %>
          <th
            :for={
              {label, column} <- [
                {gettext("Task"), :title},
                {gettext("Contact"), nil},
                {gettext("Deal"), nil},
                {gettext("Status"), nil},
                {gettext("Priority"), :priority},
                {gettext("Due"), :due_date}
              ]
            }
            class="px-3 py-3 text-left"
          >
            <%= if column do %>
              <button
                phx-click="sort"
                phx-value-by={column}
                class={[
                  "flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide transition-colors select-none",
                  if(@sort_by == column,
                    do: "text-primary",
                    else: "text-base-content/60 hover:text-base-content"
                  )
                ]}
              >
                {label} <.sort_icon active={@sort_by == column} dir={@sort_dir} />
              </button>
            <% else %>
              <span class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
                {label}
              </span>
            <% end %>
          </th>
        <% else %>
          <th
            :for={
              label <- [
                gettext("Task"),
                gettext("Contact"),
                gettext("Deal"),
                gettext("Status"),
                gettext("Priority"),
                gettext("Due")
              ]
            }
            class="px-3 py-3 text-left text-xs font-semibold uppercase tracking-wide text-base-content/60"
          >
            {label}
          </th>
        <% end %>
      </tr>
    </thead>
    """
  end

  attr :active, :boolean, required: true
  attr :dir, :atom, required: true

  defp sort_icon(assigns) do
    ~H"""
    <%= cond do %>
      <% @active and @dir == :asc -> %>
        <span class="icon-[tabler--arrow-up] size-3 text-primary" />
      <% @active and @dir == :desc -> %>
        <span class="icon-[tabler--arrow-down] size-3 text-primary" />
      <% true -> %>
        <span class="icon-[tabler--arrows-sort] size-3 opacity-30" />
    <% end %>
    """
  end

  defp total_pages(total), do: max(1, ceil(total / @per_page))

  defp page_display(_current, total_pages) when total_pages <= 7 do
    Enum.to_list(1..total_pages)
  end

  defp page_display(current, total_pages) do
    pages =
      [1, total_pages, max(2, current - 1), current, min(total_pages - 1, current + 1)]
      |> Enum.filter(&(&1 >= 1 and &1 <= total_pages))
      |> Enum.sort()
      |> Enum.uniq()

    Enum.reduce(tl(pages), [hd(pages)], fn n, acc ->
      if n - List.last(acc) > 1, do: acc ++ [:gap, n], else: acc ++ [n]
    end)
  end

  defp task_status_label(:open), do: gettext("Open")
  defp task_status_label(:in_progress), do: gettext("In progress")
  defp task_status_label(:done), do: gettext("Done")
  defp task_status_label(:cancelled), do: gettext("Cancelled")
  defp task_status_label(other), do: Phoenix.Naming.humanize(other)

  defp task_status_dot_class(:open), do: "bg-sky-500"
  defp task_status_dot_class(:in_progress), do: "bg-violet-500"
  defp task_status_dot_class(:done), do: "bg-emerald-500"
  defp task_status_dot_class(:cancelled), do: "bg-slate-400"
  defp task_status_dot_class(_), do: "bg-base-300"

  defp priority_color(:low), do: "#94a3b8"
  defp priority_color(:normal), do: "#3b82f6"
  defp priority_color(:high), do: "#f97316"
  defp priority_color(:urgent), do: "#ef4444"
  defp priority_color(_), do: "#94a3b8"

  defp task_type_icon(%{task_type: %{is_parent_only: true}}), do: "icon-[tabler--crown]"
  defp task_type_icon(%{task_type: %{name: "Epic"}}), do: "icon-[tabler--crown]"
  defp task_type_icon(%{task_type: %{name: "Task"}}), do: "icon-[tabler--menu-2]"
  defp task_type_icon(_task), do: "icon-[tabler--menu-2]"

  defp task_type_chip_style(task) do
    color = task_type_color(task)

    [
      "background-color: color-mix(in srgb, #{color} 16%, transparent)",
      "border-color: color-mix(in srgb, #{color} 42%, transparent)",
      "color: #{color}",
      "box-shadow: 0 1px 2px color-mix(in srgb, #{color} 18%, transparent), inset 0 1px 0 rgba(255, 255, 255, 0.32)"
    ]
    |> Enum.join("; ")
  end

  defp task_type_color(%{task_type: %{color: color}}) when is_binary(color) do
    if Regex.match?(~r/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/, color) do
      color
    else
      "#0ea5e9"
    end
  end

  defp task_type_color(_task), do: "#0ea5e9"

  attr(:task, :any, required: true)

  defp task_signals(assigns) do
    ~H"""
    <div
      :if={task_child_count(@task) > 0 or task_dependency_count(@task) > 0}
      class="mt-1 flex min-w-0 flex-wrap items-center gap-1.5"
    >
      <span
        :if={task_child_count(@task) > 0}
        title={gettext("Child progress")}
        class="inline-flex items-center gap-1 rounded-md border border-base-content/10 bg-base-200/60 px-1.5 py-0.5 text-[0.68rem] font-medium leading-4 text-base-content/55"
      >
        {task_completed_child_count(@task)}/{task_child_count(@task)}
      </span>
      <span
        :if={task_dependency_count(@task) > 0}
        title={dependency_signal_title(@task)}
        class={[
          "inline-flex items-center gap-1 rounded-md border px-1.5 py-0.5 text-[0.68rem] font-medium leading-4",
          if(task_blocked?(@task),
            do: "border-error/25 bg-error/10 text-error",
            else: "border-success/20 bg-success/10 text-success"
          )
        ]}
      >
        <.icon
          name={
            if(task_blocked?(@task), do: "icon-[tabler--lock]", else: "icon-[tabler--git-branch]")
          }
          class="size-3"
        />
        <%= if task_blocked?(@task) do %>
          {gettext("Blocked")}
        <% else %>
          {gettext("Deps ok")}
        <% end %>
      </span>
    </div>
    """
  end

  defp task_status(task), do: Map.get(task, :effective_status, task.status)
  defp task_status_derived?(task), do: Map.get(task, :status_derived?, false)
  defp task_blocked?(task), do: Map.get(task, :blocked?, false)
  defp task_child_count(task), do: Map.get(task, :child_count, 0)
  defp task_completed_child_count(task), do: Map.get(task, :completed_child_count, 0)
  defp task_dependency_count(task), do: Map.get(task, :dependency_count, 0)
  defp task_blocking_dependency_count(task), do: Map.get(task, :blocking_dependency_count, 0)

  defp status_readonly_reason(task) do
    cond do
      task_status_derived?(task) and task_child_count(task) > 0 ->
        gettext("Status is derived from child tasks.")

      task_status_derived?(task) ->
        gettext("Epics use derived status.")

      true ->
        nil
    end
  end

  defp complete_action_title(task) do
    cond do
      task_status(task) == :done ->
        gettext("Already complete")

      task_blocked?(task) ->
        gettext("Blocked by unfinished dependencies")

      task_child_count(task) > task_completed_child_count(task) ->
        gettext("Complete or cancel child tasks first")

      true ->
        gettext("Complete task")
    end
  end

  defp dependency_signal_title(task) do
    if task_blocked?(task) do
      ngettext(
        "1 unfinished dependency",
        "%{count} unfinished dependencies",
        task_blocking_dependency_count(task),
        count: task_blocking_dependency_count(task)
      )
    else
      gettext("All dependencies are complete.")
    end
  end

  attr(:contact, :any, required: true)

  defp task_contact_cell(assigns) do
    ~H"""
    <%= if @contact do %>
      <% full_name = contact_full_name(@contact) %>
      <div class="flex min-w-0 items-center gap-2.5">
        <%= if @contact.avatar_id do %>
          <img
            id={"task-contact-avatar-#{@contact.id}"}
            src={~p"/uploads/avatar/#{@contact.avatar_id}"}
            alt=""
            class="size-8 shrink-0 rounded-full bg-base-200 object-cover ring-1 ring-base-content/10 transition-transform group-hover:scale-105"
          />
        <% else %>
          <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary ring-1 ring-primary/10 transition-transform group-hover:scale-105">
            {contact_initial(@contact)}
          </div>
        <% end %>

        <div class="min-w-0 flex-1">
          <.link
            navigate={~p"/contacts/#{@contact}"}
            data-full-name={full_name}
            class="block truncate text-sm font-medium decoration-primary/60 underline-offset-2 transition-colors hover:text-primary hover:underline"
          >
            {display_contact_name(@contact)}
          </.link>
          <p :if={@contact.email} class="mt-0.5 truncate text-xs text-base-content/50">
            {@contact.email}
          </p>
        </div>
      </div>
    <% else %>
      <span class="text-sm text-base-content/30">—</span>
    <% end %>
    """
  end

  attr(:deal, :any, required: true)

  defp task_deal_cell(assigns) do
    ~H"""
    <%= if @deal do %>
      <span
        title={@deal.title}
        class="inline-flex items-center rounded-full border border-primary/20 bg-primary/8 px-2.5 py-1 text-xs font-semibold text-primary shadow-sm shadow-primary/5"
      >
        {"##{@deal.id}"}
      </span>
    <% else %>
      <span class="text-sm text-base-content/30">—</span>
    <% end %>
    """
  end

  defp contact_full_name(contact) do
    [contact.first_name, contact.last_name]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> case do
      "" -> contact.email || gettext("Unknown contact")
      name -> name
    end
  end

  defp display_contact_name(contact) do
    contact
    |> contact_full_name()
    |> truncate(30)
  end

  defp contact_initial(contact) do
    [contact.first_name, contact.last_name, contact.email]
    |> Enum.reject(&blank?/1)
    |> List.first("?")
    |> String.first()
  end

  defp truncate(value, max_length) when byte_size(value) > max_length do
    String.slice(value, 0, max_length - 1) <> "\u2026"
  end

  defp truncate(value, _max_length), do: value

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""

  defp format_due_date(nil), do: "—"
  defp format_due_date(date), do: Calendar.strftime(date, "%b %-d, %Y")

  # ---------------------------------------------------------------------------
  # Status pill (clickable dropdown)
  # ---------------------------------------------------------------------------

  attr(:task_id, :any, required: true)
  attr(:status, :atom, required: true)
  attr(:readonly, :boolean, default: false)
  attr(:readonly_reason, :string, default: nil)
  attr(:id_suffix, :string, default: "")

  defp status_pill(assigns) do
    all_statuses = [
      {:open, "#0ea5e9", "icon-[tabler--circle]", gettext("Open")},
      {:in_progress, "#8b5cf6", "icon-[tabler--circle-half-2]", gettext("In progress")},
      {:done, "#10b981", "icon-[tabler--circle-check-filled]", gettext("Done")},
      {:cancelled, "#94a3b8", "icon-[tabler--circle-x]", gettext("Cancelled")}
    ]

    {color, icon, label} =
      all_statuses
      |> Enum.find(
        {:unknown, "#94a3b8", "icon-[tabler--circle]", Phoenix.Naming.humanize(assigns.status)},
        fn {s, _, _, _} -> s == assigns.status end
      )
      |> then(fn {_, c, i, l} -> {c, i, l} end)

    assigns =
      assign(assigns,
        color: color,
        icon: icon,
        label: label,
        all_statuses: all_statuses
      )

    ~H"""
    <div
      id={"status-pill-#{@task_id}#{@id_suffix}"}
      phx-hook={if(@readonly, do: nil, else: "RowMenu")}
      class="relative"
    >
      <%= if @readonly do %>
        <span
          title={@readonly_reason}
          class="inline-flex w-full items-center gap-1 rounded-md border px-2.5 py-1 text-xs font-medium"
          style={pill_style_muted(@color)}
        >
          <.icon name={@icon} class="size-3.5 shrink-0" /> {@label}
        </span>
      <% else %>
        <button
          type="button"
          data-toggle
          aria-label={gettext("Change status")}
          class="inline-flex w-full cursor-pointer items-center gap-1 rounded-md border px-2.5 py-1 text-xs font-medium transition-opacity hover:opacity-80"
          style={pill_style(@color)}
        >
          <.icon name={@icon} class="size-3.5 shrink-0" /> {@label}
          <.icon name="icon-[tabler--chevron-down]" class="ml-auto size-3.5 shrink-0 opacity-60" />
        </button>
        <ul
          data-panel
          class="row-menu-closed z-50 w-44 space-y-0.5 overflow-hidden rounded-xl border border-base-content/10 bg-base-100 p-1.5 shadow-2xl shadow-base-content/15"
          role="menu"
        >
          <li :for={{val, color, icon, label} <- @all_statuses}>
            <button
              type="button"
              phx-click="update_status"
              phx-value-id={@task_id}
              phx-value-status={val}
              class="inline-flex w-full cursor-pointer items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-medium transition-opacity hover:opacity-85"
              style={pill_style_option(color, @status == val)}
              role="menuitem"
            >
              <.icon name={icon} class="size-3.5 shrink-0" /> {label}
              <.icon
                :if={@status == val}
                name="icon-[tabler--check]"
                class="ml-auto size-3 shrink-0"
              />
            </button>
          </li>
        </ul>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Priority pill (clickable dropdown)
  # ---------------------------------------------------------------------------

  attr(:task_id, :string, required: true)
  attr(:priority, :atom, required: true)
  attr(:id_suffix, :string, default: "")

  defp priority_pill(assigns) do
    all_priorities = [
      {:low, "#94a3b8", "icon-[tabler--flag-filled]", gettext("Low")},
      {:normal, "#3b82f6", "icon-[tabler--flag-filled]", gettext("Normal")},
      {:high, "#f97316", "icon-[tabler--flag-filled]", gettext("High")},
      {:urgent, "#ef4444", "icon-[tabler--flag-filled]", gettext("Urgent")}
    ]

    {color, icon, label} =
      all_priorities
      |> Enum.find(
        {:unknown, "#94a3b8", "icon-[tabler--minus]", Phoenix.Naming.humanize(assigns.priority)},
        fn {p, _, _, _} -> p == assigns.priority end
      )
      |> then(fn {_, c, i, l} -> {c, i, l} end)

    assigns =
      assign(assigns,
        color: color,
        icon: icon,
        label: label,
        all_priorities: all_priorities
      )

    ~H"""
    <div id={"priority-pill-#{@task_id}#{@id_suffix}"} phx-hook="RowMenu" class="relative">
      <button
        type="button"
        data-toggle
        aria-label={gettext("Change priority")}
        class="inline-flex w-full cursor-pointer items-center gap-1 rounded-md border px-2.5 py-1 text-xs font-medium transition-opacity hover:opacity-80"
        style={pill_style(@color)}
      >
        <span class={[@icon, "size-3.5 shrink-0"]} /> {@label}
        <span class="icon-[tabler--chevron-down] ml-auto size-3.5 shrink-0 opacity-60" />
      </button>
      <ul
        data-panel
        class="row-menu-closed z-50 w-40 space-y-0.5 overflow-hidden rounded-xl border border-base-content/10 bg-base-100 p-1.5 shadow-2xl shadow-base-content/15"
        role="menu"
      >
        <li :for={{val, color, icon, label} <- @all_priorities}>
          <button
            type="button"
            phx-click="update_priority"
            phx-value-id={@task_id}
            phx-value-priority={val}
            class="inline-flex w-full cursor-pointer items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-medium transition-opacity hover:opacity-85"
            style={pill_style_option(color, @priority == val)}
            role="menuitem"
          >
            <span class={[icon, "size-3.5 shrink-0"]} /> {label}
            <span
              :if={@priority == val}
              class="icon-[tabler--check] ml-auto size-3 shrink-0"
            />
          </button>
        </li>
      </ul>
    </div>
    """
  end

  defp pill_style(color) do
    [
      "background-color: color-mix(in srgb, #{color} 14%, transparent)",
      "border-color: color-mix(in srgb, #{color} 35%, transparent)",
      "color: #{color}"
    ]
    |> Enum.join("; ")
  end

  defp pill_style_muted(color) do
    [
      "background-color: color-mix(in srgb, var(--color-base-100) 86%, var(--color-base-200))",
      "border-color: color-mix(in srgb, #{color} 42%, var(--color-base-content) 12%)",
      "color: color-mix(in srgb, #{color} 72%, var(--color-base-content))"
    ]
    |> Enum.join("; ")
  end

  defp pill_style_option(color, active) do
    bg_pct = if active, do: "22%", else: "14%"
    border_pct = if active, do: "50%", else: "35%"

    [
      "background-color: color-mix(in srgb, #{color} #{bg_pct}, transparent)",
      "border-color: color-mix(in srgb, #{color} #{border_pct}, transparent)",
      "color: #{color}"
    ]
    |> Enum.join("; ")
  end
end
