defmodule Konevo.Contacts.Contact do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:lead, :prospect, :customer, :churned]

  schema "contacts" do
    field :first_name, :string
    field :last_name, :string
    field :slug, :string
    field :email, :string
    field :phone, :string
    field :linkedin_url, :string
    field :status, Ecto.Enum, values: @statuses, default: :lead
    field :notes, :string
    field :archived_at, :utc_datetime
    field :archive_reason, :string
    field :avatar_id, :integer, virtual: true

    belongs_to :user, Konevo.Accounts.User
    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :company, Konevo.Companies.Company
    belongs_to :archived_by, Konevo.Accounts.User

    has_many :contact_notes, Konevo.Contacts.Note
    has_many :activities, Konevo.Contacts.Activity
    has_many :deals, Konevo.Deals.Deal
    has_many :tasks, Konevo.Tasks.Task

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [
      :first_name,
      :last_name,
      :email,
      :phone,
      :linkedin_url,
      :status,
      :notes,
      :company_id
    ])
    |> validate_required([:first_name])
    |> validate_length(:first_name, max: 255)
    |> validate_length(:last_name, max: 255)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_length(:slug, max: 255)
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "must be a valid email")
    |> validate_length(:phone, max: 50)
    |> validate_length(:linkedin_url, max: 500)
    |> validate_format(:linkedin_url, ~r/^https?:\/\/(?:[\w-]+\.)?linkedin\.com\/.+/i,
      message: "must be a valid LinkedIn URL"
    )
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:slug, name: :contacts_organization_id_slug_index)
  end
end
