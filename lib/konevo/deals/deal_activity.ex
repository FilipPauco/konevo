defmodule Konevo.Deals.DealActivity do
  use Ecto.Schema
  import Ecto.Changeset

  @activity_types [:stage_change, :value_change, :note_added, :email_linked]

  schema "deal_activities" do
    field :activity_type, Ecto.Enum, values: @activity_types
    field :old_value, :string
    field :new_value, :string

    belongs_to :deal, Konevo.Deals.Deal
    belongs_to :user, Konevo.Accounts.User

    field :inserted_at, :utc_datetime, autogenerate: {DateTime, :utc_now, [:second]}
  end

  def activity_types, do: @activity_types

  @doc false
  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [:activity_type, :old_value, :new_value])
    |> validate_required([:activity_type])
  end
end
