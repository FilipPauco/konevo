defmodule Konevo.Contacts.Dedupe do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contact_dedupes" do
    field :merge_notes, :string
    field :merged_at, :utc_datetime

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :primary_contact, Konevo.Contacts.Contact
    belongs_to :duplicate_contact, Konevo.Contacts.Contact
    belongs_to :merged_by, Konevo.Accounts.User

    field :inserted_at, :utc_datetime, autogenerate: {DateTime, :utc_now, [:second]}
  end

  @doc false
  def changeset(dedupe, attrs) do
    dedupe
    |> cast(attrs, [:merge_notes, :merged_at])
    |> validate_required([:merged_at])
  end
end
