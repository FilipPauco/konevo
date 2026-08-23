defmodule Konevo.Deals.DefaultStages do
  @moduledoc false

  import Ecto.Query

  alias Konevo.Accounts.Organization
  alias Konevo.Deals.DealStage
  alias Konevo.Repo

  @stages [
    %{name: "Lead", position: 0, color: "#4b5563", is_final: false},
    %{name: "Qualified", position: 1, color: "#3b82f6", is_final: false},
    %{name: "Proposal", position: 2, color: "#f59e0b", is_final: false},
    %{name: "Negotiation", position: 3, color: "#8b5cf6", is_final: false},
    %{name: "Closed Won", position: 4, color: "#10b981", is_final: true},
    %{name: "Closed Lost", position: 5, color: "#ef4444", is_final: true}
  ]

  def ensure(%Organization{} = organization) do
    if Repo.exists?(from stage in DealStage, where: stage.organization_id == ^organization.id) do
      {:ok, :existing}
    else
      now = DateTime.utc_now(:second)

      stages =
        Enum.map(@stages, fn attrs ->
          attrs
          |> Map.put(:organization_id, organization.id)
          |> Map.put(:inserted_at, now)
          |> Map.put(:updated_at, now)
        end)

      {_, _} =
        Repo.insert_all(DealStage, stages,
          on_conflict: :nothing,
          conflict_target: [:organization_id, :position]
        )

      {:ok, :created}
    end
  end
end
