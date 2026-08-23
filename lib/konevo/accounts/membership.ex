defmodule Konevo.Accounts.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @roles [:owner, :admin, :member, :viewer]

  schema "memberships" do
    belongs_to :user, Konevo.Accounts.User
    belongs_to :organization, Konevo.Accounts.Organization

    field :role, Ecto.Enum, values: @roles, default: :member
    field :custom_permissions, {:array, :string}, default: []
    field :archived_at, :utc_datetime
    field :archive_reason, :string

    belongs_to :archived_by, Konevo.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :custom_permissions])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:user_id,
      name: :memberships_user_id_organization_id_index,
      message: "already a member of this organization"
    )
  end
end
