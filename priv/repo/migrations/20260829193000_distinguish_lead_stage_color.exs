defmodule Konevo.Repo.Migrations.DistinguishLeadStageColor do
  use Ecto.Migration
  import Ecto.Query

  def up do
    from(stage in "deal_stages",
      where:
        field(stage, :name) == "Lead" and
          field(stage, :color) in ["#38bdf8", "#4b5563", "#6b7280"]
    )
    |> repo().update_all(set: [color: "#2dd4bf"])
  end

  def down, do: :ok
end
