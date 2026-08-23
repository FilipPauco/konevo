defmodule Konevo.Inbox.EmailThread do
  use Ecto.Schema
  import Ecto.Changeset

  @categories [:lead, :customer, :support, :billing, :internal, :noise]

  schema "email_threads" do
    field :thread_id_gmail, :string
    field :thread_id_outlook, :string
    field :subject, :string
    field :category, Ecto.Enum, values: @categories
    field :snippet, :string
    field :is_unresolved, :boolean, default: true
    field :is_archived, :boolean, default: false
    field :is_favorite, :boolean, default: false
    field :read_at, :utc_datetime
    field :trashed_at, :utc_datetime
    field :revenue_at_risk, :decimal
    field :last_activity_at, :utc_datetime
    field :last_inbound_at, :utc_datetime
    field :last_outbound_at, :utc_datetime
    field :has_attachments, :boolean, default: false
    field :participants, {:array, :string}, default: []
    field :email_count, :integer, virtual: true

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :contact, Konevo.Contacts.Contact
    belongs_to :deal, Konevo.Deals.Deal

    has_many :emails, Konevo.Inbox.Email, foreign_key: :thread_id

    timestamps(type: :utc_datetime)
  end

  def categories, do: @categories

  @doc false
  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [
      :subject,
      :category,
      :snippet,
      :is_unresolved,
      :is_archived,
      :is_favorite,
      :read_at,
      :trashed_at,
      :revenue_at_risk,
      :last_activity_at,
      :last_inbound_at,
      :last_outbound_at,
      :has_attachments,
      :participants,
      :thread_id_gmail,
      :thread_id_outlook,
      :contact_id,
      :deal_id
    ])
    |> validate_required([:subject])
    |> validate_length(:subject, max: 998)
    |> validate_number(:revenue_at_risk, greater_than_or_equal_to: 0)
  end
end
