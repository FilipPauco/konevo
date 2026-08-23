defmodule Konevo.Tasks.TaskDependency do
  use Ecto.Schema
  import Ecto.Changeset

  schema "task_dependencies" do
    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :task, Konevo.Tasks.Task
    belongs_to :depends_on_task, Konevo.Tasks.Task

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task_dependency, attrs) do
    changeset =
      task_dependency
      |> cast(attrs, [:task_id, :depends_on_task_id])

    changeset
    |> validate_required([:task_id, :depends_on_task_id])
    |> validate_change(:depends_on_task_id, fn :depends_on_task_id, depends_on_task_id ->
      if get_field(changeset, :task_id) == depends_on_task_id do
        [depends_on_task_id: "cannot depend on itself"]
      else
        []
      end
    end)
    |> unique_constraint([:task_id, :depends_on_task_id])
    |> check_constraint(:depends_on_task_id, name: :task_dependency_not_self)
  end
end
