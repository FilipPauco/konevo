defmodule Konevo.Compliance.Consent do
  use Ecto.Schema
  import Ecto.Changeset

  @channels [:email, :sms]
  @statuses [:granted, :revoked]
  @sources [:manual, :import, :form, :api]

  schema "consents" do
    field :channel, Ecto.Enum, values: @channels
    field :status, Ecto.Enum, values: @statuses, default: :granted
    field :source, Ecto.Enum, values: @sources, default: :manual
    field :ip_address, :string
    field :granted_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :contact, Konevo.Contacts.Contact

    timestamps(type: :utc_datetime)
  end

  def channels, do: @channels
  def statuses, do: @statuses
  def sources, do: @sources

  @doc false
  def changeset(consent, attrs) do
    consent
    |> cast(attrs, [:channel, :status, :source, :ip_address, :granted_at, :revoked_at])
    |> validate_required([:channel, :status, :source])
  end

  @doc false
  def grant_changeset(consent, source, ip_address \\ nil) do
    consent
    |> cast(
      %{
        status: :granted,
        source: source,
        ip_address: ip_address,
        granted_at: DateTime.utc_now(:second),
        revoked_at: nil
      },
      [:status, :source, :ip_address, :granted_at, :revoked_at]
    )
  end

  @doc false
  def revoke_changeset(consent) do
    cast(consent, %{status: :revoked, revoked_at: DateTime.utc_now(:second)}, [
      :status,
      :revoked_at
    ])
  end
end
