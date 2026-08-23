defmodule Konevo.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:open, :in_progress, :done, :cancelled]
  @priorities [:low, :normal, :high, :urgent]

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :due_date, :utc_datetime
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :priority, Ecto.Enum, values: @priorities, default: :normal
    field :reminder_sent_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :position, :integer, default: 0
    field :archived_at, :utc_datetime
    field :archive_reason, :string

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :parent_task, Konevo.Tasks.Task
    belongs_to :task_type, Konevo.Tasks.TaskType
    belongs_to :contact, Konevo.Contacts.Contact
    belongs_to :company, Konevo.Companies.Company
    belongs_to :deal, Konevo.Deals.Deal
    belongs_to :assigned_to, Konevo.Accounts.User
    belongs_to :created_by, Konevo.Accounts.User
    belongs_to :completed_by, Konevo.Accounts.User
    belongs_to :source_email, Konevo.Inbox.Email
    belongs_to :source_thread, Konevo.Inbox.EmailThread
    belongs_to :archived_by, Konevo.Accounts.User

    has_many :children, Konevo.Tasks.Task, foreign_key: :parent_task_id
    has_many :reminders, Konevo.Tasks.TaskReminder
    has_many :dependencies, Konevo.Tasks.TaskDependency
    has_many :dependent_tasks, Konevo.Tasks.TaskDependency, foreign_key: :depends_on_task_id

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def priorities, do: @priorities

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :description,
      :due_date,
      :status,
      :priority,
      :position,
      :parent_task_id,
      :task_type_id,
      :contact_id,
      :company_id,
      :deal_id,
      :assigned_to_id,
      :completed_at,
      :source_email_id,
      :source_thread_id
    ])
    |> validate_required([:title, :due_date])
    |> validate_length(:title, max: 255)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities)
    |> maybe_set_completed_at()
  end

  defp maybe_set_completed_at(changeset) do
    case Ecto.Changeset.get_field(changeset, :status) do
      :done ->
        if Ecto.Changeset.get_field(changeset, :completed_at),
          do: changeset,
          else: Ecto.Changeset.put_change(changeset, :completed_at, DateTime.utc_now(:second))

      _ ->
        changeset
    end
  end
end
