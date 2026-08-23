defmodule Konevo.Workers.NoReplyFollowUpWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query, warn: false

  alias Konevo.Accounts.{Membership, Organization, Scope, User}
  alias Konevo.Automation
  alias Konevo.Automation.Sequence
  alias Konevo.Repo

  def enqueue(organization_id) when is_integer(organization_id) do
    %{"organization_id" => organization_id}
    |> new(unique: [period: 10, fields: [:worker, :args], keys: [:organization_id]])
    |> then(&Oban.insert(Konevo.Oban, &1))
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id}}) do
    organization_id
    |> active_workflow_owners()
    |> run_workflows()
  end

  def perform(%Oban.Job{}) do
    active_workflow_owners()
    |> run_workflows()
  end

  defp run_workflows(workflow_owners) do
    workflow_owners
    |> Enum.reduce_while(:ok, fn {user_id, organization_id}, :ok ->
      with {:ok, scope} <- scope_for(user_id, organization_id),
           {:ok, _drafts, []} <- Automation.prepare_active_no_reply_follow_ups(scope) do
        {:cont, :ok}
      else
        {:ok, _drafts, errors} -> {:halt, {:error, errors}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp active_workflow_owners(organization_id \\ nil) do
    Sequence
    |> where(status: :active, trigger_type: :inbound_email_idle)
    |> where([s], fragment("?->>'workflow_type' = ?", s.trigger_config, "no_reply_follow_up"))
    |> maybe_filter_organization(organization_id)
    |> select([s], {s.created_by_id, s.organization_id})
    |> distinct(true)
    |> Repo.all()
  end

  defp maybe_filter_organization(query, nil), do: query

  defp maybe_filter_organization(query, organization_id),
    do: where(query, organization_id: ^organization_id)

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
end
