defmodule Konevo.AI.ProviderSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @providers [:openai_responses]
  @key_secret "ai-provider-api-key"

  schema "ai_provider_settings" do
    field :provider, Ecto.Enum, values: @providers
    field :encrypted_api_key, :string, redact: true
    field :api_key_last4, :string
    field :monthly_budget, :decimal
    field :api_key, :string, virtual: true, redact: true

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :user, Konevo.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def providers, do: @providers

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:provider, :api_key, :monthly_budget])
    |> validate_required([:provider])
    |> validate_inclusion(:provider, @providers)
    |> validate_length(:api_key, max: 2_000)
    |> validate_number(:monthly_budget, greater_than_or_equal_to: 0)
  end

  def encrypt_api_key(api_key) when is_binary(api_key) do
    Phoenix.Token.encrypt(KonevoWeb.Endpoint, @key_secret, api_key, max_age: :infinity)
  end

  def decrypt_api_key(%__MODULE__{encrypted_api_key: encrypted}) when is_binary(encrypted) do
    Phoenix.Token.decrypt(KonevoWeb.Endpoint, @key_secret, encrypted, max_age: :infinity)
  end

  def decrypt_api_key(_setting), do: {:error, :missing_api_key}

  def masked_api_key(%__MODULE__{} = setting) do
    case decrypt_api_key(setting) do
      {:ok, api_key} -> String.slice(api_key, 0, 3) <> "*****"
      {:error, _reason} -> nil
    end
  end
end
