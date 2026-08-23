defmodule Konevo.Deals.Deal do
  use Ecto.Schema
  import Ecto.Changeset

  @currencies ~w(EUR USD GBP)
  @sources ~w(email form referral import manual api)

  schema "deals" do
    field :title, :string
    field :slug, :string
    field :description, :string
    field :value, :decimal
    field :currency, :string, default: "EUR"
    field :expected_close_date, :date
    field :probability, :integer
    field :next_action, :string
    field :next_action_due_date, :utc_datetime
    field :source, :string
    field :reason_lost, :string
    field :closed_at, :utc_datetime
    field :archived_at, :utc_datetime
    field :archive_reason, :string

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :contact, Konevo.Contacts.Contact
    belongs_to :stage, Konevo.Deals.DealStage
    belongs_to :owner, Konevo.Accounts.User
    belongs_to :created_by, Konevo.Accounts.User
    belongs_to :archived_by, Konevo.Accounts.User

    has_many :activities, Konevo.Deals.DealActivity
    has_many :tasks, Konevo.Tasks.Task

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deal, attrs) do
    deal
    |> cast(attrs, [
      :title,
      :description,
      :value,
      :currency,
      :expected_close_date,
      :probability,
      :next_action,
      :next_action_due_date,
      :source,
      :reason_lost,
      :closed_at,
      :stage_id,
      :contact_id,
      :owner_id
    ])
    |> validate_required([:title, :value, :stage_id, :contact_id])
    |> validate_length(:title, max: 255)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_length(:slug, max: 255)
    |> validate_number(:value, greater_than_or_equal_to: 0)
    |> validate_number(:probability, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:currency, @currencies)
    |> validate_inclusion(:source, @sources ++ [nil])
    |> unique_constraint(:slug, name: :deals_organization_id_slug_index)
  end
end
