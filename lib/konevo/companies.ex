defmodule Konevo.Companies do
  @moduledoc """
  The Companies context.
  """

  import Ecto.Query, warn: false
  alias Konevo.Companies.{Company, Policy}
  alias Konevo.Repo
  alias Konevo.Slugs

  @per_page 25

  @doc """
  Returns all companies belonging to the given scope's user.
  """
  def list_companies(scope) do
    scope
    |> company_base_query()
    |> filter_archive(:active)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc """
  Returns paginated companies and their contact counts.

  Supports `:search`, `:industries`, `:created_from`, `:created_to`,
  `:sort_by`, `:sort_dir`, `:page`, and `:per_page`.
  """
  def list_companies(scope, opts) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, @per_page)

    filtered =
      scope
      |> company_base_query()
      |> filter_archive(Keyword.get(opts, :archive_filter, :active))
      |> filter_search(Keyword.get(opts, :search, ""))
      |> filter_industries(Keyword.get(opts, :industries, []))
      |> filter_created_from(Keyword.get(opts, :created_from))
      |> filter_created_to(Keyword.get(opts, :created_to))

    total = Repo.aggregate(filtered, :count, :id)

    companies =
      filtered
      |> with_contact_count()
      |> sort_companies(Keyword.get(opts, :sort_by, :name), Keyword.get(opts, :sort_dir, :asc))
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Repo.all()

    {companies, total}
  end

  def list_industries(scope, opts \\ []) do
    scope
    |> company_base_query()
    |> filter_archive(Keyword.get(opts, :archive_filter, :active))
    |> where([c], not is_nil(c.industry) and c.industry != "")
    |> select([c], c.industry)
    |> distinct(true)
    |> order_by([c], asc: c.industry)
    |> Repo.all()
  end

  @doc """
  Returns up to `limit` companies matching `search` for the scope, ordered by name.
  """
  def search_companies(scope, search \\ "", limit \\ 10) do
    pattern = "%#{String.trim(search)}%"

    scope
    |> company_base_query()
    |> filter_archive(:active)
    |> where([c], ilike(c.name, ^pattern))
    |> order_by(asc: :name)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a single company in the scope's org.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_company!(scope, id) do
    scope
    |> company_base_query()
    |> where([c], c.id == ^id)
    |> preload(:contacts)
    |> Repo.one!()
  end

  def get_company_by_slug_or_id!(scope, slug_or_id) when is_binary(slug_or_id) do
    case get_company_by_slug(scope, slug_or_id) do
      nil -> get_company_by_id_param!(scope, slug_or_id)
      company -> company
    end
  end

  def get_company_by_slug_or_id!(scope, id), do: get_company!(scope, id)

  @doc """
  Creates a company.
  """
  def create_company(scope, attrs \\ %{}) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      %Company{user_id: scope.user.id, organization_id: scope.org && scope.org.id}
      |> Company.changeset(attrs)
      |> Slugs.maybe_put_slug(Company, scope.org.id, [:name])
      |> Repo.insert()
    end
  end

  @doc """
  Updates a company.
  """
  def update_company(scope, %Company{} = company, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, company: company}) do
      company
      |> Company.changeset(attrs)
      |> Slugs.maybe_put_slug(Company, scope.org.id, [:name], exclude_id: company.id)
      |> Repo.update()
    end
  end

  def authorize_company(scope, action, %Company{} = company)
      when action in [:read, :update, :delete] do
    Bodyguard.permit(Policy, action, scope.user, %{org: scope.org, company: company})
  end

  def authorize_companies(scope, action) when action in [:create, :read] do
    Bodyguard.permit(Policy, action, scope.user, %{org: scope.org})
  end

  @doc """
  Deletes a company.
  """
  def delete_company(scope, %Company{} = company) do
    with :ok <- Bodyguard.permit(Policy, :delete, scope.user, %{org: scope.org, company: company}) do
      Repo.delete(company)
    end
  end

  @doc """
  Archives a company without detaching its contacts.
  """
  def archive_company(scope, %Company{} = company, reason \\ nil) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, company: company}) do
      company
      |> Ecto.Changeset.change(archive_attrs(scope, reason))
      |> Repo.update()
    end
  end

  @doc """
  Restores an archived company.
  """
  def restore_company(scope, %Company{} = company) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, company: company}) do
      company
      |> Ecto.Changeset.change(%{archived_at: nil, archived_by_id: nil, archive_reason: nil})
      |> Repo.update()
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking company changes.
  """
  def change_company(%Company{} = company, attrs \\ %{}) do
    Company.changeset(company, attrs)
  end

  # Returns a dynamic Ecto condition scoped to org when available, otherwise user.
  defp org_condition(%{org: %{id: org_id}}), do: dynamic([c], c.organization_id == ^org_id)
  defp org_condition(%{user: %{id: user_id}}), do: dynamic([c], c.user_id == ^user_id)

  defp company_base_query(scope), do: from(c in Company, where: ^org_condition(scope))

  defp get_company_by_slug(scope, slug) do
    scope
    |> company_base_query()
    |> where([c], c.slug == ^slug)
    |> preload(:contacts)
    |> Repo.one()
  end

  defp get_company_by_id_param!(scope, value) do
    case Integer.parse(value) do
      {id, ""} -> get_company!(scope, id)
      _ -> raise Ecto.NoResultsError, queryable: Company
    end
  end

  defp filter_archive(query, :archived), do: from(c in query, where: not is_nil(c.archived_at))
  defp filter_archive(query, :all), do: query
  defp filter_archive(query, _filter), do: from(c in query, where: is_nil(c.archived_at))

  defp filter_search(query, term) when term in [nil, ""], do: query

  defp filter_search(query, term) do
    pattern = "%#{String.trim(term)}%"

    from c in query,
      where:
        ilike(c.name, ^pattern) or ilike(c.website, ^pattern) or
          ilike(c.industry, ^pattern) or ilike(c.phone, ^pattern)
  end

  defp filter_industries(query, []), do: query

  defp filter_industries(query, industries),
    do: from(c in query, where: c.industry in ^industries)

  defp filter_created_from(query, date) when date in [nil, ""], do: query

  defp filter_created_from(query, date) do
    case Date.from_iso8601(date) do
      {:ok, value} ->
        datetime = DateTime.new!(value, ~T[00:00:00], "Etc/UTC")
        from c in query, where: c.inserted_at >= ^datetime

      {:error, _reason} ->
        query
    end
  end

  defp filter_created_to(query, date) when date in [nil, ""], do: query

  defp filter_created_to(query, date) do
    case Date.from_iso8601(date) do
      {:ok, value} ->
        datetime = DateTime.new!(value, ~T[23:59:59], "Etc/UTC")
        from c in query, where: c.inserted_at <= ^datetime

      {:error, _reason} ->
        query
    end
  end

  defp with_contact_count(query) do
    counts =
      from contact in Konevo.Contacts.Contact,
        where: is_nil(contact.archived_at),
        group_by: contact.company_id,
        select: %{company_id: contact.company_id, count: count(contact.id)}

    from c in query,
      left_join: count in subquery(counts),
      on: count.company_id == c.id,
      select_merge: %{contact_count: coalesce(count.count, 0)}
  end

  defp sort_companies(query, :name, direction),
    do: from(c in query, order_by: [{^direction, c.name}])

  defp sort_companies(query, :industry, direction),
    do: from(c in query, order_by: [{^direction, c.industry}, asc: c.name])

  defp sort_companies(query, :contacts, direction),
    do: from([c, count] in query, order_by: [{^direction, coalesce(count.count, 0)}, asc: c.name])

  defp sort_companies(query, :inserted_at, direction),
    do: from(c in query, order_by: [{^direction, c.inserted_at}])

  defp sort_companies(query, _field, _direction), do: from(c in query, order_by: [asc: c.name])

  defp archive_attrs(scope, reason) do
    %{
      archived_at: DateTime.utc_now(:second),
      archived_by_id: scope.user.id,
      archive_reason: reason
    }
  end
end
