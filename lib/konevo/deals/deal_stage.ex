defmodule Konevo.Deals.DealStage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "deal_stages" do
    field :name, :string
    field :position, :integer, default: 0
    field :color, :string
    field :is_final, :boolean, default: false

    belongs_to :organization, Konevo.Accounts.Organization
    has_many :deals, Konevo.Deals.Deal, foreign_key: :stage_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(stage, attrs) do
    stage
    |> cast(attrs, [:name, :position, :color, :is_final])
    |> validate_required([:name, :position])
    |> validate_length(:name, max: 100)
    |> validate_length(:color, max: 20)
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end
end
