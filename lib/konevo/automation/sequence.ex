defmodule Konevo.Automation.Sequence do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:draft, :active, :paused, :archived]
  @trigger_types [
    :new_lead_email,
    :inbound_email_received,
    :inbound_email_idle,
    :contact_created,
    :contact_status_changed,
    :deal_created,
    :deal_stage_changed,
    :manual,
    :scheduled
  ]

  schema "automation_sequences" do
    field :name, :string
    field :description, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :trigger_type, Ecto.Enum, values: @trigger_types
    field :trigger_config, :map, default: %{}
    field :enrollment_limit, :integer
    field :activated_at, :utc_datetime

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :created_by, Konevo.Accounts.User

    has_many :rules, Konevo.Automation.Rule, foreign_key: :sequence_id
    has_many :executions, Konevo.Automation.Execution, foreign_key: :sequence_id

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def trigger_types, do: @trigger_types

  @doc false
  def changeset(sequence, attrs) do
    sequence
    |> cast(attrs, [
      :name,
      :description,
      :status,
      :trigger_type,
      :trigger_config,
      :enrollment_limit
    ])
    |> validate_required([:name, :trigger_type])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_number(:enrollment_limit, greater_than: 0)
  end
end
