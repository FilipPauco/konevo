defmodule Konevo.AI.CategorizationJob do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :processing, :completed, :failed]
  @categories [:lead, :customer, :support, :billing, :internal, :noise]

  schema "ai_categorization_jobs" do
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :result_category, Ecto.Enum, values: @categories
    field :confidence_score, :float
    field :error_message, :string
    field :processed_at, :utc_datetime

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :email_thread, Konevo.Inbox.EmailThread

    field :inserted_at, :utc_datetime, autogenerate: {DateTime, :utc_now, [:second]}
  end

  def statuses, do: @statuses
  def categories, do: @categories

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [:status, :result_category, :confidence_score, :error_message, :processed_at])
    |> validate_required([:status])
    |> validate_number(:confidence_score,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
  end

  @doc false
  def complete_changeset(job, category, confidence) do
    job
    |> cast(
      %{
        status: :completed,
        result_category: category,
        confidence_score: confidence,
        processed_at: DateTime.utc_now(:second)
      },
      [:status, :result_category, :confidence_score, :processed_at]
    )
    |> validate_required([:result_category, :confidence_score])
  end

  @doc false
  def fail_changeset(job, reason) do
    cast(
      job,
      %{status: :failed, error_message: reason, processed_at: DateTime.utc_now(:second)},
      [
        :status,
        :error_message,
        :processed_at
      ]
    )
  end
end
