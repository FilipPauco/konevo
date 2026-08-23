defmodule Konevo.Accounts.TenantInvitation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Konevo.Accounts.{Organization, User}

  schema "tenant_invitations" do
    field :email, :string
    field :token_hash, :binary
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :organization, Organization
    belongs_to :invited_by, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :token_hash, :expires_at, :organization_id, :invited_by_id])
    |> validate_required([:email, :token_hash, :expires_at, :organization_id, :invited_by_id])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> unique_constraint(:token_hash)
    |> unique_constraint(:organization_id)
  end
end
