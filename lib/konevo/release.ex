defmodule Konevo.Release do
  @moduledoc false

  @app :konevo

  def migrate_and_seed do
    migrate()
    {:ok, _} = Application.ensure_all_started(@app)
    Konevo.Accounts.ensure_essential_data()
  end

  def create_owner do
    with {:ok, _apps} <- Application.ensure_all_started(@app),
         {:ok, email} <- fetch_env("KONEVO_OWNER_EMAIL"),
         {:ok, password} <- fetch_env("KONEVO_OWNER_PASSWORD") do
      create_owner(email, password)
    end
  end

  defp create_owner(email, password) do
    case Konevo.Accounts.get_user_by_email(email) do
      nil ->
        Konevo.Accounts.register_password_owner_with_default_org(%{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        })

      _user ->
        {:ok, :already_exists}
    end
  end

  defp fetch_env(name) do
    case System.get_env(name) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: {:error, {:missing_env, name}}, else: {:ok, value}

      nil ->
        {:error, {:missing_env, name}}
    end
  end

  defp migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end
