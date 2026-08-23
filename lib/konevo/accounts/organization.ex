defmodule Konevo.Accounts.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :approval_expiry_days, :integer, default: 7
    field :archived_at, :utc_datetime

    has_many :memberships, Konevo.Accounts.Membership
    has_many :users, through: [:memberships, :user]

    timestamps(type: :utc_datetime)
  end

  def changeset(org, attrs) do
    org
    |> cast(attrs, [:name, :slug, :approval_expiry_days])
    |> validate_required([:name, :slug])
    |> validate_length(:name, max: 255)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "only lowercase letters, numbers, and hyphens"
    )
    |> validate_length(:slug, max: 63)
    |> unsafe_validate_unique(:slug, Konevo.Repo)
    |> unique_constraint(:slug)
    |> validate_number(:approval_expiry_days,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 90
    )
  end

  def approval_expiry_changeset(org, attrs) do
    cast(org, attrs, [:approval_expiry_days])
    |> validate_required([:approval_expiry_days])
    |> validate_number(:approval_expiry_days,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 90
    )
  end
end
