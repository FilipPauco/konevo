defmodule Konevo.Messaging.MessageSent do
  use Ecto.Schema
  import Ecto.Changeset

  @message_types [:email, :sms]
  @statuses [:pending, :sent, :failed, :bounced, :unsubscribed]

  schema "messages_sent" do
    field :message_type, Ecto.Enum, values: @message_types
    field :recipient, :string
    field :subject, :string
    field :body, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :sent_at, :utc_datetime
    field :opened_at, :utc_datetime
    field :clicked_at, :utc_datetime
    field :delivery_status, :string
    field :is_manual, :boolean, default: false
    field :is_automation, :boolean, default: false
    field :external_message_id, :string

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :contact, Konevo.Contacts.Contact
    belongs_to :sent_by, Konevo.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def message_types, do: @message_types
  def statuses, do: @statuses

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :message_type,
      :recipient,
      :subject,
      :body,
      :status,
      :sent_at,
      :is_manual,
      :is_automation,
      :external_message_id,
      :contact_id
    ])
    |> validate_required([:message_type, :recipient, :body])
    |> validate_length(:body, min: 1)
  end
end
