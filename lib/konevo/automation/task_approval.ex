defmodule Konevo.Automation.TaskApproval do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :approved, :rejected]
  @priorities [:low, :normal, :high, :urgent]

  schema "automation_task_approvals" do
    field :title, :string
    field :description, :string
    field :due_date, :utc_datetime
    field :priority, Ecto.Enum, values: @priorities, default: :normal
    field :confidence, :float
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :approved_at, :utc_datetime

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :sequence, Konevo.Automation.Sequence
    belongs_to :email, Konevo.Inbox.Email
    belongs_to :email_thread, Konevo.Inbox.EmailThread
    belongs_to :contact, Konevo.Contacts.Contact
    belongs_to :company, Konevo.Companies.Company
    belongs_to :approved_by, Konevo.Accounts.User
    belongs_to :created_task, Konevo.Tasks.Task

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def priorities, do: @priorities

  def changeset(task_approval, attrs) do
    task_approval
    |> cast(attrs, [
      :sequence_id,
      :email_id,
      :email_thread_id,
      :contact_id,
      :company_id,
      :title,
      :description,
      :due_date,
      :priority,
      :confidence,
      :status
    ])
    |> validate_required([:email_id, :title, :due_date, :priority])
    |> validate_length(:title, max: 255)
    |> validate_inclusion(:priority, @priorities)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end

  def approve_changeset(task_approval, user_id, task_id, attrs) do
    task_approval
    |> cast(attrs, [:title, :description, :due_date, :priority])
    |> validate_required([:title, :due_date, :priority])
    |> validate_length(:title, max: 255)
    |> validate_inclusion(:priority, @priorities)
    |> put_change(:status, :approved)
    |> put_change(:approved_by_id, user_id)
    |> put_change(:approved_at, DateTime.utc_now(:second))
    |> put_change(:created_task_id, task_id)
  end

  def reject_changeset(task_approval) do
    cast(task_approval, %{status: :rejected}, [:status])
  end
end
