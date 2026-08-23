defmodule Konevo.Compliance.SuppressionEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @channels [:email, :sms]
  @reasons [:unsubscribed, :bounced, :spam_complaint, :manual]

  schema "suppression_lists" do
    field :channel, Ecto.Enum, values: @channels
    field :value, :string
    field :reason, Ecto.Enum, values: @reasons, default: :unsubscribed

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :source_message, Konevo.Messaging.MessageSent

    field :inserted_at, :utc_datetime, autogenerate: {DateTime, :utc_now, [:second]}
  end

  def channels, do: @channels
  def reasons, do: @reasons

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:channel, :value, :reason])
    |> validate_required([:channel, :value, :reason])
    |> validate_length(:value, min: 1)
    |> unique_constraint([:organization_id, :channel, :value],
      name: :suppression_lists_organization_id_channel_value_index,
      message: "already suppressed"
    )
  end
end
