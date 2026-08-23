defmodule Konevo.AI.TaskExtraction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ai_task_extractions" do
    # Each element: %{title: String, due_date: ISO8601 | nil, confidence: float}
    field :extracted_tasks, {:array, :map}, default: []
    field :extraction_confidence, :float
    field :model_used, :string

    belongs_to :email, Konevo.Inbox.Email
    belongs_to :organization, Konevo.Accounts.Organization

    field :inserted_at, :utc_datetime, autogenerate: {DateTime, :utc_now, [:second]}
  end

  @doc false
  def changeset(extraction, attrs) do
    extraction
    |> cast(attrs, [:extracted_tasks, :extraction_confidence, :model_used])
    |> validate_required([:extracted_tasks, :extraction_confidence, :model_used])
    |> validate_number(:extraction_confidence,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> validate_length(:model_used, min: 1)
  end
end
