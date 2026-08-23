defmodule Konevo.Contacts.Activity do
  use Ecto.Schema
  import Ecto.Changeset

  @activity_types [
    :email_received,
    :email_sent,
    :sms_sent,
    :task_created,
    :deal_linked,
    :note_added
  ]

  schema "contact_activities" do
    field :activity_type, Ecto.Enum, values: @activity_types
    field :activity_date, :utc_datetime
    field :related_resource_type, :string
    field :related_resource_id, :integer
    field :summary, :string

    belongs_to :contact, Konevo.Contacts.Contact
    belongs_to :organization, Konevo.Accounts.Organization

    field :inserted_at, :utc_datetime, autogenerate: {DateTime, :utc_now, [:second]}
  end

  def activity_types, do: @activity_types

  @doc false
  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [
      :activity_type,
      :activity_date,
      :related_resource_type,
      :related_resource_id,
      :summary
    ])
    |> validate_required([:activity_type, :activity_date])
  end
end
