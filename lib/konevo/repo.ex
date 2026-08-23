defmodule Konevo.Repo do
  use Ecto.Repo,
    otp_app: :konevo,
    adapter: Ecto.Adapters.Postgres
end
