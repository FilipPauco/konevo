defmodule Konevo.Compliance.AuditLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "audit_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :integer
    field :metadata, :map, default: %{}
    field :ip_address, :string

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :actor, Konevo.Accounts.User

    field :inserted_at, :utc_datetime, autogenerate: {DateTime, :utc_now, [:second]}
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:action, :resource_type, :resource_id, :metadata, :ip_address])
    |> validate_required([:action])
    |> validate_length(:action, min: 1)
  end
end
