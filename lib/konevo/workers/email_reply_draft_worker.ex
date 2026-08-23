defmodule Konevo.Workers.EmailReplyDraftWorker do
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
         %Email{} = email <- email_for_organization(email_id, organization_id),
         {:ok, _drafts, []} <- Automation.prepare_inbound_email_replies(scope, email) do
      :ok
    else
      nil -> :ok
      {:ok, _drafts} -> :ok
      {:ok, _drafts, errors} -> {:error, errors}
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
    |> where([membership], is_nil(membership.archived_at))
    |> Repo.one()
  end

  defp email_for_organization(email_id, organization_id) do
    Email
    |> where(id: ^email_id, organization_id: ^organization_id)
    |> Repo.one()
  end
end
