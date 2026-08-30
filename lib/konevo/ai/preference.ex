defmodule Konevo.AI.Preference do
  use Ecto.Schema
  import Ecto.Changeset

  @tones ~w(professional friendly direct warm)
  @languages ["auto", "English", "Slovak"]
  @lengths ~w(concise balanced detailed)

  schema "ai_preferences" do
    field :tone, :string, default: "professional"
    field :language, :string, default: "auto"
    field :response_length, :string, default: "concise"
    field :signature, :string
    field :workspace_context, :string
    field :email_instructions, :string
    field :task_instructions, :string

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :user, Konevo.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def tones, do: @tones
  def languages, do: @languages
  def lengths, do: @lengths

  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [
      :tone,
      :language,
      :response_length,
      :signature,
      :workspace_context,
      :email_instructions,
      :task_instructions
    ])
    |> validate_required([:tone, :language, :response_length])
    |> validate_inclusion(:tone, @tones)
    |> validate_inclusion(:language, @languages)
    |> validate_inclusion(:response_length, @lengths)
    |> validate_length(:signature, max: 5_000)
    |> validate_length(:workspace_context, max: 20_000)
    |> validate_length(:email_instructions, max: 20_000)
    |> validate_length(:task_instructions, max: 10_000)
  end
end
