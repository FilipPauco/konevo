defmodule Konevo.Repo.Migrations.AlignDefaultLeadStageColor do
  use Ecto.Migration
  import Ecto.Query

  def up do
    from(stage in "deal_stages",
      where:
        field(stage, :name) == "Lead" and
          field(stage, :color) in ["#4b5563", "#6b7280"]
    )
    |> repo().update_all(set: [color: "#38bdf8"])
  end

  def down, do: :ok
end
