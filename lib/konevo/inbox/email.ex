defmodule Konevo.Inbox.Email do
  use Ecto.Schema
  import Ecto.Changeset

  schema "emails" do
    field :message_id, :string
    field :from, :string
    field :to, {:array, :string}, default: []
    field :cc, {:array, :string}, default: []
    field :bcc, {:array, :string}, default: []
    field :subject, :string
    field :body, :string
    field :html_body, :string
    field :headers, :map
    field :inline_image_cids, :map, default: %{}
    field :received_at, :utc_datetime
    field :is_inbound, :boolean
    field :has_attachments, :boolean, default: false

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :thread, Konevo.Inbox.EmailThread

    field :inserted_at, :utc_datetime, autogenerate: {DateTime, :utc_now, [:second]}
  end

  @doc false
  def changeset(email, attrs) do
    email
    |> cast(attrs, [
      :message_id,
      :from,
      :to,
      :cc,
      :bcc,
      :subject,
      :body,
      :html_body,
      :headers,
      :inline_image_cids,
      :received_at,
      :is_inbound,
      :has_attachments
    ])
    |> validate_required([:message_id, :from, :to, :received_at, :is_inbound])
    |> validate_format(:from, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "must be a valid email")
    |> unique_constraint(:message_id)
  end
end
