# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Konevo.Repo.insert!(%Konevo.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

import Ecto.Query

alias Konevo.Accounts.Organization
alias Konevo.Repo
alias Konevo.Tasks.{Task, TaskDependency, TaskType}

# Seed the reserved public tenant (accessible on the bare domain, no subdomain).
# Slug must match :default_tenant_slug in config.exs.
unless Repo.exists?(from o in Organization, where: o.slug == "public") do
  Repo.insert!(%Organization{name: "Public", slug: "public"})
  IO.puts("Seeded public tenant.")
end

now = DateTime.utc_now(:second)

task_type_defaults = [
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

ensure_task_type = fn org, attrs ->
  attrs =
    attrs
    |> Map.put(:organization_id, org.id)
    |> Map.put(:inserted_at, now)
    |> Map.put(:updated_at, now)

  Repo.insert_all(TaskType, [attrs],
    on_conflict: {:replace, [:icon, :color, :position, :is_parent_only, :updated_at]},
    conflict_target: [:organization_id, :name]
  )

  Repo.one!(from tt in TaskType, where: tt.organization_id == ^org.id and tt.name == ^attrs.name)
end

ensure_task = fn org, attrs ->
  task = Repo.one(from t in Task, where: t.organization_id == ^org.id and t.title == ^attrs.title)

  attrs =
    attrs
    |> Map.put(:organization_id, org.id)
    |> Map.put_new(:inserted_at, now)
    |> Map.put(:updated_at, now)

  if task do
    task
    |> Ecto.Changeset.change(Map.drop(attrs, [:organization_id, :inserted_at]))
    |> Repo.update!()
  else
    %Task{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end
end

ensure_dependency = fn org, task, depends_on_task ->
  %TaskDependency{
    organization_id: org.id,
    task_id: task.id,
    depends_on_task_id: depends_on_task.id
  }
  |> Repo.insert(on_conflict: :nothing, conflict_target: [:task_id, :depends_on_task_id])
end

for org <- Repo.all(Organization) do
  epic_type = ensure_task_type.(org, Enum.find(task_type_defaults, &(&1.name == "Epic")))
  task_type = ensure_task_type.(org, Enum.find(task_type_defaults, &(&1.name == "Task")))

  TaskType
  |> where([tt], tt.organization_id == ^org.id and tt.name in ["Milestone", "Section"])
  |> Repo.all()
  |> Enum.each(fn task_type ->
    task_exists? = Repo.exists?(from t in Task, where: t.task_type_id == ^task_type.id)

    if not task_exists? do
      Repo.delete!(task_type)
    end
  end)

  outreach =
    ensure_task.(org, %{
      title: "Launch outreach workspace",
      description: "Epic for the first usable task tree.",
      due_date: DateTime.add(now, 21, :day),
      status: :in_progress,
      priority: :high,
      position: 0,
      task_type_id: epic_type.id
    })

  inbox =
    ensure_task.(org, %{
      title: "Improve inbox workflow",
      description: "Epic for email-driven work.",
      due_date: DateTime.add(now, 28, :day),
      status: :open,
      priority: :normal,
      position: 1,
      task_type_id: epic_type.id
    })

  leads =
    ensure_task.(org, %{
      title: "Import first lead list",
      description: "Prepare CSV, map fields, and verify contacts.",
      due_date: DateTime.add(now, 3, :day),
      status: :open,
      priority: :urgent,
      position: 0,
      parent_task_id: outreach.id,
      task_type_id: task_type.id
    })

  followups =
    ensure_task.(org, %{
      title: "Write follow-up sequence",
      description: "Draft three short steps for warm prospects.",
      due_date: DateTime.add(now, 7, :day),
      status: :in_progress,
      priority: :high,
      position: 1,
      parent_task_id: outreach.id,
      task_type_id: task_type.id
    })

  ensure_task.(org, %{
    title: "Review Gmail sync labels",
    description: "Check which labels should become unresolved inbox items.",
    due_date: DateTime.add(now, 5, :day),
    status: :open,
    priority: :normal,
    position: 0,
    parent_task_id: inbox.id,
    task_type_id: task_type.id
  })

  ensure_task.(org, %{
    title: "Turn important emails into tasks",
    description: "Use the tree view to organize follow-up work.",
    due_date: DateTime.add(now, 10, :day),
    status: :open,
    priority: :normal,
    position: 1,
    parent_task_id: inbox.id,
    task_type_id: task_type.id
  })

  ensure_dependency.(org, followups, leads)
end

IO.puts("Seeded sample task tree data.")

# ---------------------------------------------------------------------------
# Seed deal stages for every org
# ---------------------------------------------------------------------------

alias Konevo.Deals.DefaultStages

for org <- Repo.all(Organization) do
  {:ok, _} = DefaultStages.ensure(org)
end
