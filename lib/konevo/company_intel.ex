defmodule Konevo.CompanyIntel do
  @moduledoc """
  Stores company intelligence gathered by configured providers.
  """

  import Ecto.Query, warn: false

  alias Konevo.Accounts.Scope
  alias Konevo.Companies.Company
  alias Konevo.CompanyIntel.Snapshot
  alias Konevo.Repo

  def enrich_company(%Scope{} = scope, %Company{} = company) do
    with :ok <- authorize(scope, company),
         {:ok, provider, source} <- provider_config(),
         {:ok, payload} <- provider.enrich_company(company) do
      %Snapshot{
        company_id: company.id,
        organization_id: scope.org.id,
        requested_by_id: scope.user.id
      }
      |> Snapshot.changeset(%{
        source: source,
        payload: payload,
        retrieved_at: DateTime.utc_now(:second)
      })
      |> Repo.insert()
    end
  end

  def latest_snapshot(%Scope{} = scope, %Company{} = company) do
    Snapshot
    |> where(organization_id: ^scope.org.id, company_id: ^company.id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp provider_config do
    config = Application.get_env(:konevo, :company_intel, [])

    case {Keyword.get(config, :provider), Keyword.get(config, :source)} do
      {provider, source} when is_atom(provider) and is_binary(source) and source != "" ->
        {:ok, provider, source}

      _ ->
        {:error, :provider_not_configured}
    end
  end

  defp authorize(%Scope{org: %{id: org_id}}, %Company{organization_id: org_id}), do: :ok
  defp authorize(_scope, _company), do: {:error, :unauthorized}
end
