defmodule Konevo.CompanyIntel.Snapshot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "company_intelligence_snapshots" do
    field :source, :string
    field :payload, :map, default: %{}
    field :retrieved_at, :utc_datetime

    belongs_to :company, Konevo.Companies.Company
    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :requested_by, Konevo.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:source, :payload, :retrieved_at])
    |> validate_required([:source, :payload, :retrieved_at])
    |> validate_length(:source, max: 100)
  end
end
