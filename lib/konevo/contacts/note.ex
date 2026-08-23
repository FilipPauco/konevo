defmodule Konevo.Contacts.Note do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contact_notes" do
    field :body, :string
    field :is_internal, :boolean, default: false

    belongs_to :contact, Konevo.Contacts.Contact
    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :created_by, Konevo.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(note, attrs) do
    note
    |> cast(attrs, [:body, :is_internal])
    |> validate_required([:body])
    |> validate_length(:body, min: 1)
  end
end
