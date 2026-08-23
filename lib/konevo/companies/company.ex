defmodule Konevo.Companies.Company do
  use Ecto.Schema
  import Ecto.Changeset

  schema "companies" do
    field :name, :string
    field :slug, :string
    field :website, :string
    field :linkedin_url, :string
    field :industry, :string
    field :phone, :string
    field :notes, :string
    field :archived_at, :utc_datetime
    field :archive_reason, :string
    field :contact_count, :integer, virtual: true, default: 0

    belongs_to :user, Konevo.Accounts.User
    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :archived_by, Konevo.Accounts.User
    has_many :contacts, Konevo.Contacts.Contact
    has_many :tasks, Konevo.Tasks.Task

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(company, attrs) do
    company
    |> cast(attrs, [:name, :website, :linkedin_url, :industry, :phone, :notes])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_length(:slug, max: 255)
    |> validate_length(:website, max: 255)
    |> validate_length(:linkedin_url, max: 500)
    |> validate_length(:industry, max: 255)
    |> validate_length(:phone, max: 50)
    |> validate_format(:website, ~r/^https?:\/\/[^\s]+$/,
      message: "must start with http:// or https://"
    )
    |> validate_format(:linkedin_url, ~r/^https?:\/\/(?:[\w-]+\.)?linkedin\.com\/.+/i,
      message: "must be a valid LinkedIn URL"
    )
    |> unique_constraint(:slug, name: :companies_organization_id_slug_index)
  end
end
