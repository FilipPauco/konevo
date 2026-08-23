defmodule Konevo.Automation.Execution do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :running, :completed, :failed, :cancelled]

  schema "automation_executions" do
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :enrolled_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :error_message, :string
    field :metadata, :map, default: %{}

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :sequence, Konevo.Automation.Sequence
    belongs_to :contact, Konevo.Contacts.Contact
    belongs_to :current_rule, Konevo.Automation.Rule

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [:status, :enrolled_at, :completed_at, :error_message, :metadata])
    |> validate_required([:status, :enrolled_at])
  end

  @doc false
  def advance_changeset(execution, next_rule) do
    execution
    |> change(status: :running, current_rule_id: next_rule.id)
  end

  @doc false
  def complete_changeset(execution) do
    execution
    |> change(status: :completed, completed_at: DateTime.utc_now(:second), current_rule_id: nil)
  end

  @doc false
  def fail_changeset(execution, reason) do
    execution
    |> change(status: :failed, error_message: reason, completed_at: DateTime.utc_now(:second))
  end

  @doc false
  def cancel_changeset(execution) do
    execution
    |> change(status: :cancelled, completed_at: DateTime.utc_now(:second))
  end
end
