defmodule Konevo.Workers.EmailTaskExtractionWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query, warn: false

  alias Konevo.Accounts.{Membership, Organization, Scope, User}
  alias Konevo.Automation
  alias Konevo.Inbox.Email
  alias Konevo.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "email_id" => email_id,
          "organization_id" => organization_id,
          "user_id" => user_id
        }
      }) do
    with {:ok, scope} <- scope_for(user_id, organization_id),
         %Email{} = email <- Repo.get(Email, email_id),
         {:ok, _results, []} <- Automation.prepare_inbound_email_tasks(scope, email) do
      :ok
    else
      nil -> :ok
      {:ok, _results} -> :ok
      {:ok, _results, errors} -> {:error, errors}
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{}), do: :ok

  defp scope_for(user_id, organization_id) do
    with %User{} = user <- Repo.get(User, user_id),
         %Organization{} = org <- Repo.get(Organization, organization_id),
         %Membership{} = membership <- active_membership(user, org) do
      {:ok, Scope.for_user_in_org(user, org, membership)}
    else
      nil -> {:error, :missing_scope}
    end
  end

  defp active_membership(%User{id: user_id}, %Organization{id: organization_id}) do
    Membership
    |> where(user_id: ^user_id, organization_id: ^organization_id)
    |> where([m], is_nil(m.archived_at))
    |> Repo.one()
  end
end
