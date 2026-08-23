defmodule Konevo.Automation.Rule do
  use Ecto.Schema
  import Ecto.Changeset

  @action_types [
    :prepare_follow_up,
    :prepare_task,
    :prepare_reply,
    :send_email,
    :send_sms,
    :create_task,
    :wait,
    :update_contact_status,
    :add_tag,
    :alert_owner,
    :notify_owner
  ]

  schema "automation_rules" do
    field :position, :integer, default: 0
    field :action_type, Ecto.Enum, values: @action_types
    field :action_config, :map, default: %{}
    # seconds to wait before executing this step (0 = immediate)
    field :delay_seconds, :integer, default: 0

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :sequence, Konevo.Automation.Sequence

    timestamps(type: :utc_datetime)
  end

  def action_types, do: @action_types

  @doc false
  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:position, :action_type, :action_config, :delay_seconds])
    |> validate_required([:action_type, :position])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_number(:delay_seconds, greater_than_or_equal_to: 0)
  end
end
