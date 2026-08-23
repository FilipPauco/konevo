defmodule Konevo.Repo.Migrations.AddTaskTreeSupport do
  use Ecto.Migration

  def change do
    create table(:task_types) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :icon, :string
      add :color, :string
      add :position, :integer, null: false, default: 0
      add :is_parent_only, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:task_types, [:organization_id])
    create unique_index(:task_types, [:organization_id, :name])

    alter table(:tasks) do
      add :parent_task_id, references(:tasks, on_delete: :nilify_all)
      add :task_type_id, references(:task_types, on_delete: :nilify_all)
      add :position, :integer, null: false, default: 0
    end

    create index(:tasks, [:parent_task_id])
    create index(:tasks, [:task_type_id])
    create index(:tasks, [:organization_id, :parent_task_id, :position])

    create table(:task_dependencies) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :depends_on_task_id, references(:tasks, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:task_dependencies, [:organization_id])
    create index(:task_dependencies, [:task_id])
    create index(:task_dependencies, [:depends_on_task_id])
    create unique_index(:task_dependencies, [:task_id, :depends_on_task_id])

    create constraint(:task_dependencies, :task_dependency_not_self,
             check: "task_id <> depends_on_task_id"
           )
  end
end
