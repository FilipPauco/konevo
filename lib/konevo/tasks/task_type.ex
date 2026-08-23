defmodule Konevo.Tasks.TaskType do
  use Ecto.Schema
  import Ecto.Changeset

  schema "task_types" do
    field :name, :string
    field :icon, :string
    field :color, :string
    field :position, :integer, default: 0
    field :is_parent_only, :boolean, default: false

    belongs_to :organization, Konevo.Accounts.Organization
    has_many :tasks, Konevo.Tasks.Task

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task_type, attrs) do
    task_type
    |> cast(attrs, [:name, :icon, :color, :position, :is_parent_only])
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> validate_length(:icon, max: 80)
    |> validate_length(:color, max: 32)
    |> unique_constraint([:organization_id, :name])
  end
end
