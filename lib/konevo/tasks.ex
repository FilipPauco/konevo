defmodule Konevo.Tasks do
  @moduledoc """
  The Tasks context — tasks, reminders, and completion tracking.
  """

  import Ecto.Query, warn: false

  alias Konevo.Companies.Company
  alias Konevo.Contacts.Contact
  alias Konevo.Deals.Deal
  alias Konevo.Repo
  alias Konevo.Tasks.{Policy, Task, TaskDependency, TaskReminder, TaskType}

  @per_page 25
  @complete_statuses [:done, :cancelled]
  @calendar_statuses [:open, :in_progress]
  @status_values [:open, :in_progress, :done, :cancelled]
  @status_by_param Map.new(@status_values, &{Atom.to_string(&1), &1})
  @default_task_types [
    %{
      name: "Epic",
      icon: "icon-[tabler--crown]",
      color: "#f59e0b",
      position: 0,
      is_parent_only: true
    },
    %{
      name: "Task",
      icon: "icon-[tabler--menu-2]",
      color: "#0ea5e9",
      position: 1,
      is_parent_only: false
    }
  ]
  @legacy_default_task_type_names ["Milestone", "Section"]
  @task_attr_keys %{
    "title" => :title,
    "description" => :description,
    "due_date" => :due_date,
    "status" => :status,
    "priority" => :priority,
    "position" => :position,
    "parent_task_id" => :parent_task_id,
    "task_type_id" => :task_type_id,
    "contact_id" => :contact_id,
    "company_id" => :company_id,
    "deal_id" => :deal_id,
    "assigned_to_id" => :assigned_to_id,
    "completed_at" => :completed_at,
    "source_email_id" => :source_email_id,
    "source_thread_id" => :source_thread_id
  }

  # ---------------------------------------------------------------------------
  # Tasks
  # ---------------------------------------------------------------------------

  @doc """
  Returns paginated tasks for the scope's org.

  Options:
    - `:status`      – atom or list of atoms to filter by
    - `:contact_id`  – filter by contact
    - `:deal_id`     – filter by deal
    - `:assigned_to` – user_id to filter by
    - `:overdue`     – boolean; true returns only overdue open tasks
    - `:sort_by`     – `:due_date` | `:inserted_at` | `:priority`
    - `:sort_dir`    – `:asc` | `:desc`
    - `:page`        – 1-based integer
    - `:per_page`    – integer (defaults to #{@per_page})

  Returns `{tasks, total_count}`.
  """
  def list_tasks(scope, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, @per_page)

    filtered =
      scope
      |> task_base_query()
      |> filter_archive(Keyword.get(opts, :archive_filter, :active))
      |> filter_search(Keyword.get(opts, :search))
      |> filter_status(Keyword.get(opts, :status))
      |> filter_priority(Keyword.get(opts, :priority))
      |> filter_contact(Keyword.get(opts, :contact_id))
      |> filter_company(Keyword.get(opts, :company_id))
      |> filter_deal(Keyword.get(opts, :deal_id))
      |> filter_assigned_to(Keyword.get(opts, :assigned_to))
      |> filter_overdue(Keyword.get(opts, :overdue))
      |> filter_due_from(Keyword.get(opts, :due_from))
      |> filter_due_to(Keyword.get(opts, :due_to))

    total = Repo.aggregate(filtered, :count, :id)

    tasks =
      filtered
      |> sort_tasks(Keyword.get(opts, :sort_by, :due_date), Keyword.get(opts, :sort_dir, :asc))
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> preload([:task_type, :contact, :company, :deal, :assigned_to, :parent_task])
      |> Repo.all()

    {tasks, total}
  end

  @doc """
  Returns active tasks due inside the given calendar range.
  """
  def list_calendar_tasks(scope, %DateTime{} = starts_at, %DateTime{} = ends_at) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      tasks =
        scope
        |> task_base_query()
        |> filter_archive(:active)
        |> where(
          [t],
          t.status in ^@calendar_statuses and t.due_date >= ^starts_at and t.due_date < ^ends_at
        )
        |> order_by([t], asc: t.due_date, asc: t.id)
        |> preload([
          :task_type,
          :company,
          :assigned_to,
          contact: :company,
          deal: [contact: :company]
        ])
        |> Repo.all()

      {:ok, tasks}
    end
  end

  @doc """
  Returns active tasks linked directly to a contact or through one of its deals.
  """
  def list_tasks_for_contact(scope, %Contact{} = contact, opts \\ []) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}),
         true <- same_org?(scope, contact) do
      tasks =
        scope
        |> task_base_query()
        |> filter_archive(:active)
        |> join(:left, [t], d in assoc(t, :deal))
        |> where([t, d], t.contact_id == ^contact.id or d.contact_id == ^contact.id)
        |> timeline_order()
        |> timeline_limit(opts)
        |> preload([:task_type, :contact, :company, :deal, :assigned_to])
        |> Repo.all()

      {:ok, tasks}
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc """
  Returns active tasks linked directly to a company.
  """
  def list_tasks_for_company(scope, %Company{} = company, opts \\ []) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}),
         true <- same_org?(scope, company) do
      tasks =
        scope
        |> task_base_query()
        |> filter_archive(:active)
        |> filter_company(company.id)
        |> timeline_order()
        |> timeline_limit(opts)
        |> preload([:task_type, :contact, :company, :deal, :assigned_to])
        |> Repo.all()

      {:ok, tasks}
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc """
  Returns active tasks created from an inbox thread.
  """
  def list_tasks_for_source_thread(scope, thread_id) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      tasks =
        scope
        |> task_base_query()
        |> filter_archive(:active)
        |> where([t], t.source_thread_id == ^thread_id)
        |> timeline_order()
        |> preload([:task_type, :contact, :company, :deal, :assigned_to, :parent_task])
        |> Repo.all()

      {:ok, tasks}
    end
  end

  @doc """
  Returns org task types, creating the small default set for new orgs.
  """
  def list_task_types(scope) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      ensure_default_task_types(scope)

      types =
        TaskType
        |> where(organization_id: ^scope.org.id)
        |> order_by([tt], asc: tt.position, asc: tt.name)
        |> Repo.all()

      {:ok, types}
    end
  end

  @doc """
  Returns direct children for a parent task, enriched for tree rendering.
  """
  def list_tree_tasks(scope, opts \\ []) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      parent_task_id = Keyword.get(opts, :parent_task_id)
      depth = Keyword.get(opts, :depth, 0)
      archive_filter = Keyword.get(opts, :archive_filter, :active)

      tasks =
        scope
        |> task_base_query()
        |> filter_archive(archive_filter)
        |> filter_parent(parent_task_id)
        |> order_by([t], asc: t.position, asc: t.due_date, asc: t.id)
        |> preload([:task_type, :assigned_to, :contact, :company, :deal, :parent_task])
        |> Repo.all()

      {:ok, attach_tree_metadata(scope, tasks, depth, archive_filter)}
    end
  end

  @doc """
  Returns lightweight task options for parent/dependency selects.
  """
  def list_task_options(scope) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      options =
        scope
        |> task_base_query()
        |> filter_archive(:active)
        |> join(:left, [t], tt in assoc(t, :task_type))
        |> order_by([t], asc: t.position, asc: t.due_date, asc: t.id)
        |> select([t, tt], %{
          id: t.id,
          title: t.title,
          parent_task_id: t.parent_task_id,
          task_type_id: t.task_type_id,
          task_type_parent_only?: coalesce(tt.is_parent_only, false)
        })
        |> Repo.all()

      {:ok, options}
    end
  end

  @doc """
  Adds a dependency between two tasks in the same org.
  """
  def add_dependency(scope, %Task{} = task, %Task{} = depends_on_task) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, task: task}),
         true <- same_org?(scope, task),
         true <- same_org?(scope, depends_on_task),
         :ok <- validate_dependency_cycle(scope, task, depends_on_task) do
      %TaskDependency{organization_id: scope.org.id}
      |> TaskDependency.changeset(%{
        task_id: task.id,
        depends_on_task_id: depends_on_task.id
      })
      |> Repo.insert()
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc """
  Removes a dependency from a task.
  """
  def delete_dependency(scope, %Task{} = task, dependency_id) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, task: task}),
         %TaskDependency{} = dependency <- get_dependency(scope, task, dependency_id) do
      Repo.delete(dependency)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Gets a single task scoped to org, preloading associations.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_task!(scope, id) do
    Task
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> preload([
      :task_type,
      :parent_task,
      :contact,
      :company,
      :deal,
      :assigned_to,
      :reminders,
      :source_email,
      :source_thread
    ])
    |> Repo.one!()
    |> attach_task_metadata(scope)
  end

  @doc """
  Creates a task.
  """
  def create_task(scope, attrs \\ %{}) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      Repo.transaction(fn -> create_task_transaction(scope, attrs) end)
    end
  end

  defp create_task_transaction(scope, attrs) do
    with {:ok, attrs} <- prepare_tree_attrs(scope, attrs),
         :ok <- validate_new_task_status(scope, attrs),
         {:ok, task} <-
           %Task{organization_id: scope.org.id, created_by_id: scope.user.id}
           |> Task.changeset(attrs)
           |> Repo.insert() do
      task
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc """
  Returns the epic an email-sourced task would be filed under, without creating it.
  """
  def suggested_parent_epic(scope, %Task{} = task) do
    suggested_parent_epic(scope, task_suggestion_attrs(task))
  end

  def suggested_parent_epic(scope, attrs) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      attrs =
        attrs
        |> normalize_task_attrs()
        |> maybe_put_company_from_relation(scope)

      if should_auto_parent_email_task?(scope, attrs) do
        {:ok, parent_epic_preview(scope, attrs)}
      else
        {:ok, nil}
      end
    end
  end

  defp task_suggestion_attrs(task) do
    Map.take(task, [
      :parent_task_id,
      :task_type_id,
      :contact_id,
      :company_id,
      :deal_id,
      :source_email_id,
      :source_thread_id
    ])
  end

  @doc """
  Returns true when at least one task has already been created from an email.
  """
  def source_email_task_exists?(scope, email_id) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      scope
      |> task_base_query()
      |> where([t], t.source_email_id == ^email_id)
      |> Repo.exists?()
    end
  end

  @doc """
  Updates a task.
  """
  def update_task(scope, %Task{} = task, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, task: task}),
         {:ok, attrs} <- prepare_tree_attrs(scope, attrs, task),
         :ok <- validate_status_update(scope, task, attrs) do
      task
      |> Task.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Marks a task as done.
  """
  def complete_task(scope, %Task{} = task) do
    update_task(scope, task, %{status: :done, completed_by_id: scope.user.id})
  end

  @doc """
  Deletes a task and all its descendants recursively.

  Returns:
  - `{:ok, task}` on success
  - `{:error, :unauthorized}` if user lacks permission
  - `{:error, :has_contact_or_deal}` if task is linked to a contact or deal
  - `{:error, :has_dependents}` if other tasks depend on this task
  """
  def delete_task(scope, %Task{} = task) do
    with :ok <- Bodyguard.permit(Policy, :delete, scope.user, %{org: scope.org, task: task}),
         :ok <- check_task_references(task) do
      Repo.transaction(fn -> delete_task_recursive(scope, task) end)
      |> case do
        {:ok, _} -> {:ok, task}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp check_task_references(%Task{contact_id: cid, deal_id: did})
       when not is_nil(cid) or not is_nil(did),
       do: {:error, :has_contact_or_deal}

  defp check_task_references(_task), do: :ok

  defp delete_task_recursive(scope, %Task{} = task) do
    has_dependents =
      Repo.exists?(
        from d in TaskDependency,
          where: d.depends_on_task_id == ^task.id and d.organization_id == ^scope.org.id
      )

    if has_dependents, do: Repo.rollback(:has_dependents)

    task
    |> task_children_query(scope)
    |> Repo.all()
    |> Enum.each(&delete_task_recursive(scope, &1))

    Repo.delete!(task)
  end

  @doc """
  Archives a task and all descendants.
  """
  def archive_task(scope, %Task{} = task, reason \\ nil) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, task: task}) do
      task = get_task_record!(scope, task.id)
      attrs = archive_attrs(scope, reason)

      Repo.transaction(fn ->
        archive_task_recursive(scope, task, attrs)
      end)
      |> case do
        {:ok, archived_task} -> {:ok, archived_task}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Restores an archived task, its ancestors, and descendants.
  """
  def restore_task(scope, %Task{} = task) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, task: task}) do
      task = get_task_record!(scope, task.id)

      Repo.transaction(fn ->
        restore_task_ancestors(scope, task)
        restore_task_recursive(scope, task)
      end)
      |> case do
        {:ok, restored_task} -> {:ok, restored_task}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Returns a changeset for tracking task changes.
  """
  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  @doc """
  Returns counts of tasks grouped by status for the scope's org.
  """
  def count_tasks_by_status(scope) do
    scope
    |> task_base_query()
    |> filter_archive(:active)
    |> group_by([t], t.status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Task Reminders
  # ---------------------------------------------------------------------------

  @doc """
  Adds a reminder to a task.
  """
  def add_reminder(scope, %Task{} = task, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, task: task}) do
      %TaskReminder{task_id: task.id}
      |> TaskReminder.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Deletes a task reminder.
  """
  def delete_reminder(scope, %Task{} = task, %TaskReminder{} = reminder) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, task: task}) do
      Repo.delete(reminder)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp task_base_query(%{org: %{id: org_id}}) do
    from(t in Task, where: t.organization_id == ^org_id)
  end

  defp task_base_query(%Task{organization_id: org_id}) when not is_nil(org_id) do
    from(t in Task, where: t.organization_id == ^org_id)
  end

  defp get_task_record!(scope, id) do
    Task
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> Repo.one!()
  end

  defp filter_archive(query, :archived), do: from(t in query, where: not is_nil(t.archived_at))
  defp filter_archive(query, :all), do: query
  defp filter_archive(query, _filter), do: from(t in query, where: is_nil(t.archived_at))

  defp archive_task_recursive(scope, %Task{} = task, attrs) do
    task
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!()

    task
    |> task_children_query(scope)
    |> Repo.all()
    |> Enum.each(&archive_task_recursive(scope, &1, attrs))

    %{task | archived_at: attrs.archived_at, archived_by_id: attrs.archived_by_id}
  end

  defp restore_task_recursive(scope, %Task{} = task) do
    task
    |> Ecto.Changeset.change(%{archived_at: nil, archived_by_id: nil, archive_reason: nil})
    |> Repo.update!()

    task
    |> task_children_query(scope)
    |> Repo.all()
    |> Enum.each(&restore_task_recursive(scope, &1))

    %{task | archived_at: nil, archived_by_id: nil, archive_reason: nil}
  end

  defp restore_task_ancestors(scope, %Task{parent_task_id: nil}), do: scope

  defp restore_task_ancestors(scope, %Task{parent_task_id: parent_task_id}) do
    parent =
      Task
      |> where(id: ^parent_task_id, organization_id: ^scope.org.id)
      |> Repo.one()

    case parent do
      nil ->
        scope

      %Task{} = task ->
        restore_task_ancestors(scope, task)

        task
        |> Ecto.Changeset.change(%{archived_at: nil, archived_by_id: nil, archive_reason: nil})
        |> Repo.update!()

        scope
    end
  end

  defp task_children_query(%Task{} = task, scope) do
    from(t in Task, where: t.parent_task_id == ^task.id and t.organization_id == ^scope.org.id)
  end

  defp archive_attrs(scope, reason) do
    %{
      archived_at: DateTime.utc_now(:second),
      archived_by_id: scope.user.id,
      archive_reason: reason
    }
  end

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query

  defp filter_search(query, search) when is_binary(search) do
    pattern = "%#{search}%"
    from(t in query, where: ilike(t.title, ^pattern))
  end

  defp filter_priority(query, nil), do: query
  defp filter_priority(query, []), do: query

  defp filter_priority(query, priorities) when is_list(priorities),
    do: from(t in query, where: t.priority in ^priorities)

  defp filter_due_from(query, nil), do: query

  defp filter_due_from(query, %Date{} = date) do
    dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    from(t in query, where: t.due_date >= ^dt)
  end

  defp filter_due_to(query, nil), do: query

  defp filter_due_to(query, %Date{} = date) do
    dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
    from(t in query, where: t.due_date <= ^dt)
  end

  defp filter_parent(query, nil), do: from(t in query, where: is_nil(t.parent_task_id))

  defp filter_parent(query, parent_id),
    do: from(t in query, where: t.parent_task_id == ^parent_id)

  defp filter_status(query, nil), do: query
  defp filter_status(query, []), do: query

  defp filter_status(query, statuses) when is_list(statuses),
    do: from(t in query, where: t.status in ^statuses)

  defp filter_status(query, status), do: from(t in query, where: t.status == ^status)

  defp filter_contact(query, nil), do: query
  defp filter_contact(query, id), do: from(t in query, where: t.contact_id == ^id)

  defp filter_company(query, nil), do: query
  defp filter_company(query, id), do: from(t in query, where: t.company_id == ^id)

  defp filter_deal(query, nil), do: query
  defp filter_deal(query, id), do: from(t in query, where: t.deal_id == ^id)

  defp filter_assigned_to(query, nil), do: query

  defp filter_assigned_to(query, user_id),
    do: from(t in query, where: t.assigned_to_id == ^user_id)

  defp filter_overdue(query, true) do
    now = DateTime.utc_now(:second)
    from(t in query, where: t.status in [:open, :in_progress] and t.due_date < ^now)
  end

  defp filter_overdue(query, _), do: query

  defp timeline_order(query), do: from(t in query, order_by: [desc: t.due_date, desc: t.id])

  defp timeline_limit(query, opts) do
    limit = Keyword.get(opts, :limit, 8)
    from(t in query, limit: ^limit)
  end

  defp ensure_default_task_types(scope) do
    now = DateTime.utc_now(:second)

    rows =
      Enum.map(@default_task_types, fn attrs ->
        attrs
        |> Map.put_new(:is_parent_only, false)
        |> Map.put(:organization_id, scope.org.id)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(TaskType, rows,
      on_conflict: {:replace, [:icon, :color, :position, :is_parent_only, :updated_at]},
      conflict_target: [:organization_id, :name]
    )

    delete_unused_legacy_task_types(scope)
  end

  defp prepare_tree_attrs(scope, attrs, task \\ nil) do
    attrs =
      attrs
      |> normalize_task_attrs()
      |> normalize_due_date()
      |> maybe_put_company_from_relation(scope)

    attrs =
      if is_nil(task) do
        attrs
        |> maybe_put_default_type(scope)
        |> maybe_put_email_parent_epic(scope)
        |> maybe_put_position(scope)
      else
        attrs
      end

    with :ok <- validate_parent_task(scope, attrs, task),
         :ok <- validate_task_type(scope, attrs),
         :ok <- validate_task_type_parent(scope, attrs, task),
         :ok <- validate_company(scope, attrs) do
      {:ok, attrs}
    end
  end

  defp maybe_put_default_type(attrs, scope) do
    task_type_id = Map.get(attrs, :task_type_id) || Map.get(attrs, "task_type_id")

    if blank?(task_type_id) do
      ensure_default_task_types(scope)
      Map.put(attrs, :task_type_id, default_task_type_id(scope))
    else
      attrs
    end
  end

  defp maybe_put_position(attrs, scope) do
    position = Map.get(attrs, :position) || Map.get(attrs, "position")

    if blank?(position) do
      Map.put(attrs, :position, next_position(scope, parent_id_from(attrs)))
    else
      attrs
    end
  end

  defp parent_id_from(attrs),
    do: Map.get(attrs, :parent_task_id)

  defp maybe_put_email_parent_epic(attrs, scope) do
    if should_auto_parent_email_task?(scope, attrs) do
      attrs
      |> parent_epic_for_attrs(scope)
      |> case do
        {:ok, parent} -> Map.put(attrs, :parent_task_id, parent.id)
        {:error, reason} -> Repo.rollback(reason)
      end
    else
      attrs
    end
  end

  defp should_auto_parent_email_task?(scope, attrs) do
    email_sourced_task?(attrs) and blank?(Map.get(attrs, :parent_task_id)) and
      not task_type_parent_only?(scope, normalize_id(Map.get(attrs, :task_type_id)))
  end

  defp email_sourced_task?(attrs) do
    not blank?(Map.get(attrs, :source_email_id)) or not blank?(Map.get(attrs, :source_thread_id))
  end

  defp parent_epic_for_attrs(attrs, scope) do
    attrs
    |> parent_epic_identity(scope)
    |> find_or_create_parent_epic(scope)
  end

  defp parent_epic_preview(scope, attrs) do
    attrs
    |> parent_epic_identity(scope)
    |> Map.take([:title, :icon])
  end

  defp parent_epic_identity(attrs, scope) do
    company_id = normalize_id(Map.get(attrs, :company_id))
    contact_id = normalize_id(Map.get(attrs, :contact_id))

    cond do
      company_id ->
        company_epic_identity(scope, company_id)

      contact_id ->
        contact_epic_identity(scope, contact_id)

      true ->
        %{title: "Other", icon: "icon-[tabler--inbox]"}
    end
  end

  defp company_epic_identity(scope, company_id) do
    case get_company(scope, company_id) do
      %Company{} = company ->
        %{
          title: "Company - #{company.name}",
          company_id: company.id,
          icon: "icon-[tabler--building]"
        }

      nil ->
        %{title: "Other", icon: "icon-[tabler--inbox]"}
    end
  end

  defp contact_epic_identity(scope, contact_id) do
    case get_contact(scope, contact_id) do
      %Contact{company_id: company_id} when not is_nil(company_id) ->
        company_epic_identity(scope, company_id)

      %Contact{} = contact ->
        %{
          title: "Contact - #{contact_name(contact)}",
          contact_id: contact.id,
          icon: "icon-[tabler--user]"
        }

      nil ->
        %{title: "Other", icon: "icon-[tabler--inbox]"}
    end
  end

  defp find_or_create_parent_epic(identity, scope) do
    case find_parent_epic(scope, identity) do
      %Task{} = task -> {:ok, task}
      nil -> create_parent_epic(scope, identity)
    end
  end

  defp find_parent_epic(scope, identity) do
    epic_type_id = epic_task_type_id(scope)

    scope
    |> task_base_query()
    |> filter_archive(:active)
    |> where([t], is_nil(t.parent_task_id) and t.task_type_id == ^epic_type_id)
    |> filter_parent_epic_identity(identity)
    |> order_by([t], asc: t.id)
    |> limit(1)
    |> Repo.one()
  end

  defp filter_parent_epic_identity(query, %{company_id: company_id}) do
    from(t in query, where: t.company_id == ^company_id)
  end

  defp filter_parent_epic_identity(query, %{contact_id: contact_id}) do
    from(t in query, where: t.contact_id == ^contact_id and is_nil(t.company_id))
  end

  defp filter_parent_epic_identity(query, %{title: title}) do
    from(
      t in query,
      where:
        t.title == ^title and is_nil(t.company_id) and is_nil(t.contact_id) and is_nil(t.deal_id)
    )
  end

  defp create_parent_epic(scope, identity) do
    attrs =
      identity
      |> Map.take([:title, :company_id, :contact_id])
      |> Map.merge(%{
        due_date: DateTime.add(DateTime.utc_now(:second), 30, :day),
        status: :open,
        priority: :normal,
        position: next_position(scope, nil),
        task_type_id: epic_task_type_id(scope)
      })

    %Task{organization_id: scope.org.id, created_by_id: scope.user.id}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  defp epic_task_type_id(scope) do
    ensure_default_task_types(scope)

    TaskType
    |> where(organization_id: ^scope.org.id, name: "Epic", is_parent_only: true)
    |> select([tt], tt.id)
    |> Repo.one()
  end

  defp default_task_type_id(scope) do
    TaskType
    |> where(organization_id: ^scope.org.id, is_parent_only: false)
    |> order_by([tt], asc: tt.position, asc: tt.name)
    |> select([tt], tt.id)
    |> limit(1)
    |> Repo.one()
  end

  defp next_position(scope, parent_task_id) do
    scope
    |> task_base_query()
    |> filter_archive(:active)
    |> filter_parent(normalize_id(parent_task_id))
    |> select([t], coalesce(max(t.position), -1) + 1)
    |> Repo.one()
  end

  defp normalize_id(value) when value in [nil, ""], do: nil
  defp normalize_id(value) when is_integer(value), do: value

  defp normalize_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp blank?(value), do: value in [nil, ""]

  defp validate_parent_task(scope, attrs, task) do
    parent_id = normalize_id(parent_id_from(attrs))

    if valid_parent_task?(scope, task, parent_id),
      do: :ok,
      else: {:error, :invalid_parent_task}
  end

  defp valid_parent_task?(_scope, _task, nil), do: true
  defp valid_parent_task?(_scope, %Task{id: id}, id), do: false

  defp valid_parent_task?(scope, %Task{id: id}, parent_id) do
    not child_path_exists?(scope, id, parent_id) and parent_task_exists?(scope, parent_id)
  end

  defp valid_parent_task?(scope, _task, parent_id), do: parent_task_exists?(scope, parent_id)

  defp parent_task_exists?(scope, parent_id) do
    Repo.exists?(
      from(t in Task,
        where:
          t.id == ^parent_id and t.organization_id == ^scope.org.id and
            is_nil(t.archived_at)
      )
    )
  end

  defp validate_task_type(scope, attrs) do
    task_type_id = normalize_id(Map.get(attrs, :task_type_id))

    cond do
      is_nil(task_type_id) ->
        :ok

      Repo.exists?(
        from(tt in TaskType,
          where: tt.id == ^task_type_id and tt.organization_id == ^scope.org.id
        )
      ) ->
        :ok

      true ->
        {:error, :invalid_task_type}
    end
  end

  defp validate_task_type_parent(scope, attrs, task) do
    parent_id = parent_id_from(attrs, task)
    task_type_id = task_type_id_from(attrs, task)

    if parent_id && task_type_parent_only?(scope, task_type_id) do
      {:error, :invalid_parent_task}
    else
      :ok
    end
  end

  defp parent_id_from(attrs, nil), do: normalize_id(parent_id_from(attrs))

  defp parent_id_from(attrs, %Task{} = task) do
    if Map.has_key?(attrs, :parent_task_id) do
      attrs |> Map.get(:parent_task_id) |> normalize_id()
    else
      task.parent_task_id
    end
  end

  defp task_type_id_from(attrs, nil), do: normalize_id(Map.get(attrs, :task_type_id))

  defp task_type_id_from(attrs, %Task{} = task) do
    attrs
    |> Map.get(:task_type_id, task.task_type_id)
    |> normalize_id()
  end

  defp validate_company(scope, attrs) do
    company_id = normalize_id(Map.get(attrs, :company_id))

    cond do
      is_nil(company_id) ->
        :ok

      Repo.exists?(
        from(c in Company, where: c.id == ^company_id and c.organization_id == ^scope.org.id)
      ) ->
        :ok

      true ->
        {:error, :invalid_company}
    end
  end

  defp maybe_put_company_from_relation(attrs, scope) do
    if blank?(Map.get(attrs, :company_id)) do
      case company_id_from_contact(scope, normalize_id(Map.get(attrs, :contact_id))) ||
             company_id_from_deal(scope, normalize_id(Map.get(attrs, :deal_id))) do
        nil -> attrs
        company_id -> Map.put(attrs, :company_id, company_id)
      end
    else
      attrs
    end
  end

  defp company_id_from_contact(_scope, nil), do: nil

  defp company_id_from_contact(scope, contact_id) do
    Contact
    |> where(id: ^contact_id, organization_id: ^scope.org.id)
    |> select([c], c.company_id)
    |> Repo.one()
  end

  defp company_id_from_deal(_scope, nil), do: nil

  defp company_id_from_deal(scope, deal_id) do
    Deal
    |> where(id: ^deal_id, organization_id: ^scope.org.id)
    |> join(:inner, [d], c in assoc(d, :contact))
    |> select([_d, c], c.company_id)
    |> Repo.one()
  end

  defp get_company(scope, company_id) do
    Company
    |> where(id: ^company_id, organization_id: ^scope.org.id)
    |> Repo.one()
  end

  defp get_contact(scope, contact_id) do
    Contact
    |> where(id: ^contact_id, organization_id: ^scope.org.id)
    |> Repo.one()
  end

  defp contact_name(contact) do
    [contact.first_name, contact.last_name]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> case do
      "" -> contact.email || "Unknown contact"
      name -> name
    end
  end

  defp normalize_task_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_binary(key) ->
        case Map.fetch(@task_attr_keys, key) do
          {:ok, atom_key} -> Map.put(acc, atom_key, value)
          :error -> acc
        end

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp normalize_due_date(%{due_date: due_date} = attrs) when is_binary(due_date) do
    with {:error, _reason} <- put_naive_due_date(attrs, due_date),
         {:error, _reason} <- put_naive_due_date(attrs, due_date <> ":00") do
      attrs
    else
      {:ok, attrs} -> attrs
    end
  end

  defp normalize_due_date(attrs), do: attrs

  defp put_naive_due_date(attrs, due_date) do
    case NaiveDateTime.from_iso8601(due_date) do
      {:ok, naive} -> {:ok, Map.put(attrs, :due_date, DateTime.from_naive!(naive, "Etc/UTC"))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_unused_legacy_task_types(scope) do
    TaskType
    |> where(
      [tt],
      tt.organization_id == ^scope.org.id and tt.name in ^@legacy_default_task_type_names
    )
    |> Repo.all()
    |> Enum.each(fn task_type ->
      task_exists? = Repo.exists?(from(t in Task, where: t.task_type_id == ^task_type.id))

      if not task_exists? do
        Repo.delete(task_type)
      end
    end)
  end

  defp attach_tree_metadata(scope, tasks, depth, archive_filter) do
    task_ids = Enum.map(tasks, & &1.id)
    child_counts = child_counts(scope, task_ids, archive_filter)
    child_progress = child_progress(scope, task_ids, archive_filter)
    dependency_counts = dependency_counts(scope, task_ids)
    blocking_dependency_counts = blocking_dependency_counts(scope, task_ids)

    Enum.map(tasks, fn task ->
      child_count = Map.get(child_counts, task.id, 0)
      progress = Map.get(child_progress, task.id, empty_child_progress())
      blocking_dependency_count = Map.get(blocking_dependency_counts, task.id, 0)
      status_derived? = task_parent_only?(scope, task) or child_count > 0

      task
      |> Map.put(:depth, depth)
      |> Map.put(:child_count, child_count)
      |> Map.put(:completed_child_count, progress.done + progress.cancelled)
      |> Map.put(:open_child_count, child_count - progress.done - progress.cancelled)
      |> Map.put(:dependency_count, Map.get(dependency_counts, task.id, 0))
      |> Map.put(:blocking_dependency_count, blocking_dependency_count)
      |> Map.put(:blocked?, blocking_dependency_count > 0)
      |> Map.put(:status_derived?, status_derived?)
      |> Map.put(:effective_status, effective_status(task.status, progress, status_derived?))
      |> Map.put(:has_children?, child_count > 0)
    end)
  end

  defp attach_task_metadata(%Task{} = task, scope) do
    child_count = child_count(scope, task.id)
    progress = child_progress(scope, [task.id]) |> Map.get(task.id, empty_child_progress())
    dependency_count = dependency_count(scope, task.id)
    blocking_dependency_count = blocking_dependency_count(scope, task.id)
    status_derived? = task_parent_only?(scope, task) or child_count > 0

    task
    |> Map.put(:depth, 0)
    |> Map.put(:child_count, child_count)
    |> Map.put(:completed_child_count, progress.done + progress.cancelled)
    |> Map.put(:open_child_count, child_count - progress.done - progress.cancelled)
    |> Map.put(:dependency_count, dependency_count)
    |> Map.put(:blocking_dependency_count, blocking_dependency_count)
    |> Map.put(:blocked?, blocking_dependency_count > 0)
    |> Map.put(:status_derived?, status_derived?)
    |> Map.put(:effective_status, effective_status(task.status, progress, status_derived?))
    |> Map.put(:has_children?, child_count > 0)
  end

  defp child_counts(scope, task_ids, archive_filter)

  defp child_counts(_scope, [], _archive_filter), do: %{}

  defp child_counts(scope, task_ids, archive_filter) do
    scope
    |> task_base_query()
    |> filter_archive(archive_filter)
    |> where([t], t.parent_task_id in ^task_ids)
    |> group_by([t], t.parent_task_id)
    |> select([t], {t.parent_task_id, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp child_count(scope, task_id, archive_filter \\ :active) do
    scope
    |> task_base_query()
    |> filter_archive(archive_filter)
    |> where([t], t.parent_task_id == ^task_id)
    |> Repo.aggregate(:count, :id)
  end

  defp child_progress(scope, task_ids, archive_filter \\ :active)

  defp child_progress(_scope, [], _archive_filter), do: %{}

  defp child_progress(scope, task_ids, archive_filter) do
    scope
    |> task_base_query()
    |> filter_archive(archive_filter)
    |> where([t], t.parent_task_id in ^task_ids)
    |> group_by([t], [t.parent_task_id, t.status])
    |> select([t], {t.parent_task_id, t.status, count(t.id)})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {parent_id, status, count}, acc ->
      Map.update(
        acc,
        parent_id,
        init_child_progress(status, count),
        &merge_child_progress(&1, status, count)
      )
    end)
  end

  defp init_child_progress(status, count),
    do: empty_child_progress() |> merge_child_progress(status, count)

  defp merge_child_progress(progress, status, count),
    do: Map.update!(progress, status, &(&1 + count))

  defp empty_child_progress, do: %{open: 0, in_progress: 0, done: 0, cancelled: 0}

  defp effective_status(status, _progress, false), do: status

  defp effective_status(status, %{open: 0, in_progress: 0, done: 0, cancelled: 0}, true),
    do: status

  defp effective_status(_status, progress, true) do
    total = progress.open + progress.in_progress + progress.done + progress.cancelled

    cond do
      progress.cancelled == total -> :cancelled
      progress.done + progress.cancelled == total -> :done
      progress.in_progress > 0 or progress.done > 0 or progress.cancelled > 0 -> :in_progress
      true -> :open
    end
  end

  defp dependency_counts(_scope, []), do: %{}

  defp dependency_counts(scope, task_ids) do
    TaskDependency
    |> where(organization_id: ^scope.org.id)
    |> where([td], td.task_id in ^task_ids)
    |> group_by([td], td.task_id)
    |> select([td], {td.task_id, count(td.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp dependency_count(scope, task_id) do
    TaskDependency
    |> where(organization_id: ^scope.org.id, task_id: ^task_id)
    |> Repo.aggregate(:count, :id)
  end

  defp blocking_dependency_counts(_scope, []), do: %{}

  defp blocking_dependency_counts(scope, task_ids) do
    TaskDependency
    |> join(:inner, [td], t in Task, on: t.id == td.depends_on_task_id)
    |> where([td, t], td.organization_id == ^scope.org.id and td.task_id in ^task_ids)
    |> where([_td, t], t.status not in ^@complete_statuses and is_nil(t.archived_at))
    |> group_by([td, _t], td.task_id)
    |> select([td, _t], {td.task_id, count(td.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp blocking_dependency_count(scope, task_id) do
    blocking_dependency_counts(scope, [task_id])
    |> Map.get(task_id, 0)
  end

  defp get_dependency(scope, task, dependency_id) do
    TaskDependency
    |> where(
      [td],
      td.id == ^dependency_id and td.task_id == ^task.id and td.organization_id == ^scope.org.id
    )
    |> Repo.one()
  end

  defp same_org?(scope, %Task{organization_id: org_id}), do: scope.org.id == org_id

  defp same_org?(scope, %{organization_id: org_id}), do: scope.org.id == org_id

  defp validate_new_task_status(scope, attrs) do
    task_type_id = normalize_id(Map.get(attrs, :task_type_id))

    case changed_status(attrs) do
      {:ok, status} ->
        if task_type_parent_only?(scope, task_type_id) and status != :open do
          {:error, :parent_status_is_derived}
        else
          :ok
        end

      :unchanged ->
        :ok

      :invalid ->
        :ok
    end
  end

  defp validate_status_update(scope, task, attrs) do
    with {:ok, status} <- changed_status(attrs),
         :ok <- validate_done_status(scope, task, status) do
      if status_derived_task?(scope, task, attrs) do
        {:error, :parent_status_is_derived}
      else
        :ok
      end
    else
      :unchanged -> :ok
      :invalid -> :ok
      error -> error
    end
  end

  defp validate_done_status(scope, task, :done) do
    cond do
      blocking_dependency_count(scope, task.id) > 0 -> {:error, :task_has_open_dependencies}
      open_child_count(scope, task.id) > 0 -> {:error, :task_has_open_children}
      true -> :ok
    end
  end

  defp validate_done_status(_scope, _task, _status), do: :ok

  defp changed_status(attrs) do
    case Map.fetch(attrs, :status) do
      {:ok, status} -> normalize_status(status)
      :error -> :unchanged
    end
  end

  defp normalize_status(status) when status in @status_values, do: {:ok, status}

  defp normalize_status(status) when is_binary(status) do
    case Map.fetch(@status_by_param, status) do
      {:ok, status} -> {:ok, status}
      :error -> :invalid
    end
  end

  defp normalize_status(_status), do: :invalid

  defp open_child_count(scope, task_id) do
    scope
    |> task_base_query()
    |> filter_archive(:active)
    |> where([t], t.parent_task_id == ^task_id and t.status not in ^@complete_statuses)
    |> Repo.aggregate(:count, :id)
  end

  defp status_derived_task?(scope, task, attrs) do
    task_type_id = Map.get(attrs, :task_type_id) || task.task_type_id
    task_type_parent_only?(scope, normalize_id(task_type_id)) or child_count(scope, task.id) > 0
  end

  defp task_parent_only?(_scope, %{task_type: %{is_parent_only: is_parent_only}})
       when is_boolean(is_parent_only),
       do: is_parent_only

  defp task_parent_only?(scope, %{task_type_id: task_type_id}),
    do: task_type_parent_only?(scope, task_type_id)

  defp task_type_parent_only?(_scope, nil), do: false

  defp task_type_parent_only?(scope, task_type_id) do
    TaskType
    |> where(id: ^task_type_id, organization_id: ^scope.org.id, is_parent_only: true)
    |> Repo.exists?()
  end

  defp validate_dependency_cycle(_scope, %Task{id: id}, %Task{id: id}),
    do: {:error, :invalid_dependency}

  defp validate_dependency_cycle(scope, task, depends_on_task) do
    if dependency_path_exists?(scope, depends_on_task.id, task.id) do
      {:error, :dependency_cycle}
    else
      :ok
    end
  end

  defp dependency_path_exists?(scope, from_task_id, target_task_id) do
    dependency_path_exists?(scope, [from_task_id], target_task_id, MapSet.new())
  end

  defp dependency_path_exists?(_scope, [], _target_task_id, _visited), do: false

  defp dependency_path_exists?(scope, task_ids, target_task_id, visited) do
    task_ids = Enum.reject(task_ids, &MapSet.member?(visited, &1))

    cond do
      task_ids == [] ->
        false

      target_task_id in task_ids ->
        true

      true ->
        next_task_ids =
          TaskDependency
          |> where([td], td.organization_id == ^scope.org.id and td.task_id in ^task_ids)
          |> select([td], td.depends_on_task_id)
          |> Repo.all()

        visited = Enum.reduce(task_ids, visited, &MapSet.put(&2, &1))
        dependency_path_exists?(scope, next_task_ids, target_task_id, visited)
    end
  end

  defp child_path_exists?(scope, task_id, target_child_id) do
    child_path_exists?(scope, [task_id], target_child_id, MapSet.new())
  end

  defp child_path_exists?(_scope, [], _target_child_id, _visited), do: false

  defp child_path_exists?(scope, parent_ids, target_child_id, visited) do
    parent_ids = Enum.reject(parent_ids, &MapSet.member?(visited, &1))

    cond do
      parent_ids == [] ->
        false

      target_child_id in parent_ids ->
        true

      true ->
        child_ids =
          scope
          |> task_base_query()
          |> filter_archive(:active)
          |> where([t], t.parent_task_id in ^parent_ids)
          |> select([t], t.id)
          |> Repo.all()

        visited = Enum.reduce(parent_ids, visited, &MapSet.put(&2, &1))
        child_path_exists?(scope, child_ids, target_child_id, visited)
    end
  end

  defp sort_tasks(query, :title, dir), do: from(t in query, order_by: [{^dir, t.title}])

  defp sort_tasks(query, :priority, dir) do
    priority_order =
      Ecto.Query.dynamic(
        [t],
        fragment(
          "CASE ? WHEN 'urgent' THEN 4 WHEN 'high' THEN 3 WHEN 'normal' THEN 2 ELSE 1 END",
          t.priority
        )
      )

    from(t in query, order_by: [{^dir, ^priority_order}, {^dir, t.due_date}])
  end

  defp sort_tasks(query, :inserted_at, dir),
    do: from(t in query, order_by: [{^dir, t.inserted_at}])

  defp sort_tasks(query, _field, dir), do: from(t in query, order_by: [{^dir, t.due_date}])
end
