defmodule Konevo.Search do
  @moduledoc """
  Cross-record search for the authenticated organization.
  """

  alias Konevo.Accounts.Scope
  alias Konevo.{Companies, Contacts, Deals, Inbox, Tasks}

  @default_limit 5

  @doc """
  Searches contacts, companies, deals, tasks, and inbox threads in the scope.
  """
  def search(scope, query, limit \\ @default_limit)

  def search(%Scope{user: %{id: _}, org: %{id: _}} = scope, query, limit)
      when is_binary(query) and is_integer(limit) and limit > 0 do
    query = String.trim(query)

    if query == "" do
      {:ok, []}
    else
      {:ok,
       contact_results(scope, query, limit) ++
         company_results(scope, query, limit) ++
         deal_results(scope, query, limit) ++
         task_results(scope, query, limit) ++
         thread_results(scope, query, limit)}
    end
  end

  def search(_scope, _query, _limit), do: {:error, :invalid_scope}

  defp contact_results(scope, query, limit) do
    scope
    |> Contacts.search_contacts(query, limit)
    |> Enum.map(fn contact ->
      result(:contact, contact.id, contact_name(contact), contact.email)
    end)
  end

  defp company_results(scope, query, limit) do
    scope
    |> Companies.search_companies(query, limit)
    |> Enum.map(fn company -> result(:company, company.id, company.name, company.industry) end)
  end

  defp deal_results(scope, query, limit) do
    scope
    |> Deals.list_deals(search: query, limit: limit)
    |> Enum.map(fn deal ->
      subtitle =
        Enum.join(Enum.reject([contact_name(deal.contact), deal.stage.name], &blank?/1), " - ")

      result(:deal, deal.id, deal.title, subtitle)
    end)
  end

  defp task_results(scope, query, limit) do
    {tasks, _total} = Tasks.list_tasks(scope, search: query, per_page: limit)

    Enum.map(tasks, fn task ->
      subtitle =
        Enum.join(
          Enum.reject([task.company && task.company.name, contact_name(task.contact)], &blank?/1),
          " - "
        )

      result(:task, task.id, task.title, subtitle)
    end)
  end

  defp thread_results(scope, query, limit) do
    case Inbox.list_threads(scope, search: query, per_page: limit) do
      {threads, _total} when is_list(threads) ->
        Enum.map(threads, fn thread ->
          result(
            :thread,
            thread.id,
            thread.subject,
            List.first(thread.participants) || thread.snippet
          )
        end)

      {:error, _reason} ->
        []
    end
  end

  defp result(type, id, title, subtitle) do
    %{type: type, id: id, title: title || "", subtitle: subtitle || ""}
  end

  defp contact_name(nil), do: nil

  defp contact_name(contact) do
    [contact.first_name, contact.last_name]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp blank?(value), do: value in [nil, ""]
end
