defmodule Konevo.Inbox.EmailIntegration do
  use Ecto.Schema
  import Ecto.Changeset

  @providers [:gmail, :outlook, :smtp]

  schema "email_integrations" do
    field :provider, Ecto.Enum, values: @providers
    field :email_address, :string
    field :access_token, :binary
    field :refresh_token, :binary
    field :token_expires_at, :utc_datetime
    field :is_primary, :boolean, default: false
    field :sync_enabled, :boolean, default: true
    field :last_sync_at, :utc_datetime
    field :signature_html, :string
    field :history_import_status, :string, default: "idle"
    field :history_import_started_at, :utc_datetime
    field :history_import_completed_at, :utc_datetime
    field :history_imported_threads, :integer, default: 0
    field :history_processed_threads, :integer, default: 0
    field :history_import_error, :string

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :user, Konevo.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def providers, do: @providers

  @doc false
  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [
      :provider,
      :email_address,
      :is_primary,
      :sync_enabled
    ])
    |> validate_required([:provider, :email_address])
    |> validate_format(:email_address, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must be a valid email"
    )
    |> validate_inclusion(:provider, @providers)
    |> unique_constraint([:organization_id, :email_address])
  end

  @doc false
  def branding_changeset(integration, attrs) do
    integration
    |> cast(attrs, [:signature_html])
    |> validate_length(:signature_html, max: 20_000)
  end

  @doc false
  def token_changeset(integration, attrs) do
    integration
    |> cast(attrs, [:access_token, :refresh_token, :token_expires_at, :last_sync_at])
  end

  @doc false
  def history_import_changeset(integration, attrs) do
    integration
    |> cast(attrs, [
      :history_import_status,
      :history_import_started_at,
      :history_import_completed_at,
      :history_imported_threads,
      :history_processed_threads,
      :history_import_error
    ])
  end
end
