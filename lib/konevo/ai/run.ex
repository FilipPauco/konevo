defmodule Konevo.AI.Run do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :completed, :failed]

  schema "ai_runs" do
    field :kind, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :provider, :string
    field :model_used, :string
    field :input, :map, default: %{}
    field :output, :map, default: %{}
    field :error_message, :string
    field :input_tokens, :integer
    field :output_tokens, :integer

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :user, Konevo.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :kind,
      :status,
      :provider,
      :model_used,
      :input,
      :output,
      :error_message,
      :input_tokens,
      :output_tokens
    ])
    |> validate_required([:kind, :status])
    |> validate_length(:kind, max: 100)
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
  end
end
