defmodule Konevo.CompanyIntel.Provider do
  @moduledoc false

  @callback enrich_company(Konevo.Companies.Company.t()) :: {:ok, map()} | {:error, term()}
end
