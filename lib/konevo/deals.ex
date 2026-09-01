defmodule Konevo.Deals do
  @moduledoc """
  The Deals context — pipeline stages, deals, and deal activity log.
  """

  import Ecto.Query, warn: false

  alias Konevo.Deals.{Deal, DealActivity, DealStage, Policy}
  alias Konevo.Repo
  alias Konevo.Slugs

  # ---------------------------------------------------------------------------
  # Deal Stages
  # ---------------------------------------------------------------------------

  @doc """
  Returns all deal stages for the scope's org, ordered by position.
  """
  def list_stages(scope) do
    from(s in DealStage,
      where: s.organization_id == ^scope.org.id,
      order_by: [asc: s.position]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single deal stage scoped to org.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_stage!(scope, id) do
    DealStage
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> Repo.one!()
  end

  @doc """
  Creates a deal stage.
  """
  def create_stage(scope, attrs \\ %{}) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      %DealStage{organization_id: scope.org.id}
      |> DealStage.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates a deal stage.
  """
  def update_stage(scope, %DealStage{} = stage, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org}) do
      stage
      |> DealStage.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Deletes a deal stage.
  """
  def delete_stage(scope, %DealStage{} = stage) do
    with :ok <- Bodyguard.permit(Policy, :delete, scope.user, %{org: scope.org}) do
      Repo.delete(stage)
    end
  end

  @doc """
  Returns a changeset for tracking stage changes.
  """
  def change_stage(%DealStage{} = stage, attrs \\ %{}) do
    DealStage.changeset(stage, attrs)
  end

  # ---------------------------------------------------------------------------
  # Deals
  # ---------------------------------------------------------------------------

  @doc """
  Returns all deals for the scope's org, preloading stage and contact.

  Options:
    - `:contact_id` – filter by contact
    - `:company_id` – filter through linked contacts
    - `:stage_id`   – filter by stage
    - `:stage_ids`  – filter by stages
    - `:search`     – search title, contact name, or contact email
    - `:min_value`  – minimum deal value
    - `:min_probability` – minimum win probability
    - `:close_from` – earliest expected close date
    - `:close_to`   – latest expected close date
    - `:sources`    – filter by deal sources
    - `:sort_by`    – `:inserted_at` | `:value` | `:expected_close_date`
    - `:sort_dir`   – `:asc` | `:desc`
  """
  def list_deals(scope, opts \\ []) do
    base = deals_base_query(scope)

    base
    |> filter_archive(Keyword.get(opts, :archive_filter, :active))
    |> search_deals(Keyword.get(opts, :search))
    |> filter_by_contact(Keyword.get(opts, :contact_id))
    |> filter_by_company(Keyword.get(opts, :company_id))
    |> filter_by_stage(Keyword.get(opts, :stage_id))
    |> filter_by_stages(Keyword.get(opts, :stage_ids, []))
    |> filter_by_min_value(Keyword.get(opts, :min_value))
    |> filter_by_min_probability(Keyword.get(opts, :min_probability))
    |> filter_by_close_from(Keyword.get(opts, :close_from))
    |> filter_by_close_to(Keyword.get(opts, :close_to))
    |> filter_by_sources(Keyword.get(opts, :sources, []))
    |> sort_deals(Keyword.get(opts, :sort_by, :inserted_at), Keyword.get(opts, :sort_dir, :desc))
    |> maybe_limit(Keyword.get(opts, :limit))
    |> preload([:stage, :contact, :owner])
    |> Repo.all()
  end

  @doc """
  Returns a capped, filterable set of deals for each Kanban stage plus totals.
  """
  def list_deals_for_kanban(scope, stage_limits, opts \\ []) when is_map(stage_limits) do
    base =
      scope
      |> deals_base_query()
      |> filter_archive(Keyword.get(opts, :archive_filter, :active))
      |> search_deals(Keyword.get(opts, :search))
      |> filter_by_stages(Keyword.get(opts, :stage_ids, []))
      |> filter_by_min_value(Keyword.get(opts, :min_value))
      |> filter_by_min_probability(Keyword.get(opts, :min_probability))
      |> filter_by_close_from(Keyword.get(opts, :close_from))
      |> filter_by_close_to(Keyword.get(opts, :close_to))
      |> filter_by_sources(Keyword.get(opts, :sources, []))

    stage_ids = Map.keys(stage_limits)

    stage_counts =
      base
      |> filter_by_stages(stage_ids)
      |> group_by([d], d.stage_id)
      |> select([d], {d.stage_id, count(d.id)})
      |> Repo.all()
      |> Map.new()

    deals_by_stage =
      Map.new(stage_limits, fn {stage_id, limit} ->
        deals =
          base
          |> filter_by_stage(stage_id)
          |> sort_deals(:inserted_at, :asc)
          |> maybe_limit(limit)
          |> preload([:stage, :contact, :owner])
          |> Repo.all()

        {stage_id, deals}
      end)

    total = Repo.aggregate(base, :count, :id)
    pipeline_total = Repo.one(from d in base, select: sum(d.value)) || Decimal.new(0)

    %{
      deals_by_stage: deals_by_stage,
      stage_counts: stage_counts,
      total: total,
      pipeline_total: pipeline_total
    }
  end

  @doc """
  Returns open deal next actions inside the given calendar range.
  """
  def list_calendar_deal_actions(scope, %DateTime{} = starts_at, %DateTime{} = ends_at) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      deals =
        from(d in Deal,
          where:
            d.organization_id == ^scope.org.id and is_nil(d.closed_at) and
              is_nil(d.archived_at) and
              not is_nil(d.next_action_due_date) and d.next_action_due_date >= ^starts_at and
              d.next_action_due_date < ^ends_at,
          order_by: [asc: d.next_action_due_date, asc: d.id],
          preload: [:stage, :owner, contact: :company]
        )
        |> Repo.all()

      {:ok, deals}
    end
  end

  @doc """
  Returns open deal close dates inside the given calendar date range.
  """
  def list_calendar_deal_close_dates(scope, %Date{} = starts_on, %Date{} = ends_on) do
    with :ok <- Bodyguard.permit(Policy, :read, scope.user, %{org: scope.org}) do
      deals =
        from(d in Deal,
          where:
            d.organization_id == ^scope.org.id and is_nil(d.closed_at) and
              is_nil(d.archived_at) and
              not is_nil(d.expected_close_date) and d.expected_close_date >= ^starts_on and
              d.expected_close_date < ^ends_on,
          order_by: [asc: d.expected_close_date, asc: d.id],
          preload: [:stage, :owner, contact: :company]
        )
        |> Repo.all()

      {:ok, deals}
    end
  end

  @doc """
  Gets a single deal scoped to org, preloading stage, contact, and activities.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_deal!(scope, id) do
    Deal
    |> where(id: ^id, organization_id: ^scope.org.id)
    |> preload([:stage, :contact, :owner, :activities])
    |> Repo.one!()
  end

  def get_deal_by_slug_or_id!(scope, slug_or_id) when is_binary(slug_or_id) do
    case get_deal_by_slug(scope, slug_or_id) do
      nil -> get_deal_by_id_param!(scope, slug_or_id)
      deal -> deal
    end
  end

  def get_deal_by_slug_or_id!(scope, id), do: get_deal!(scope, id)

  @doc """
  Creates a deal.
  """
  def create_deal(scope, attrs \\ %{}) do
    with :ok <- Bodyguard.permit(Policy, :create, scope.user, %{org: scope.org}) do
      %Deal{organization_id: scope.org.id, created_by_id: scope.user.id}
      |> Deal.changeset(attrs)
      |> Slugs.maybe_put_slug(Deal, scope.org.id, [:title])
      |> Repo.insert()
    end
  end

  @doc """
  Updates a deal. Records a stage_change activity when the stage changes.
  """
  def update_deal(scope, %Deal{} = deal, attrs) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, deal: deal}) do
      changeset =
        deal
        |> Deal.changeset(attrs)
        |> Slugs.maybe_put_slug(Deal, scope.org.id, [:title], exclude_id: deal.id)

      Repo.transaction(fn ->
        updated = Repo.update!(changeset)
        maybe_record_stage_change(updated, deal, changeset, scope.user.id)
        updated
      end)
    end
  end

  @doc """
  Deletes a deal.
  """
  def delete_deal(scope, %Deal{} = deal) do
    with :ok <- Bodyguard.permit(Policy, :delete, scope.user, %{org: scope.org, deal: deal}) do
      Repo.delete(deal)
    end
  end

  @doc """
  Archives a deal while preserving linked tasks, emails, and activity.
  """
  def archive_deal(scope, %Deal{} = deal, reason \\ nil) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, deal: deal}) do
      deal
      |> Ecto.Changeset.change(archive_attrs(scope, reason))
      |> Repo.update()
    end
  end

  @doc """
  Restores an archived deal.
  """
  def restore_deal(scope, %Deal{} = deal) do
    with :ok <- Bodyguard.permit(Policy, :update, scope.user, %{org: scope.org, deal: deal}) do
      deal
      |> Ecto.Changeset.change(%{archived_at: nil, archived_by_id: nil, archive_reason: nil})
      |> Repo.update()
    end
  end

  @doc """
  Moves a deal to a different stage.
  """
  def move_deal_to_stage(scope, deal_id, stage_id)
      when is_integer(deal_id) and is_integer(stage_id) do
    deal = get_deal!(scope, deal_id)
    update_deal(scope, deal, %{stage_id: stage_id})
  end

  @doc """
  Returns a changeset for tracking deal changes.
  """
  def change_deal(%Deal{} = deal, attrs \\ %{}) do
    Deal.changeset(deal, attrs)
  end

  @doc """
  Returns pipeline summary for the scope's org:
  total value and count grouped by stage.
  """
  def pipeline_summary(scope) do
    from(d in Deal,
      join: s in assoc(d, :stage),
      where: d.organization_id == ^scope.org.id and is_nil(d.archived_at),
      group_by: [s.id, s.name, s.position, s.color],
      select: %{
        stage_id: s.id,
        stage_name: s.name,
        position: s.position,
        color: s.color,
        count: count(d.id),
        total_value: coalesce(sum(d.value), 0)
      },
      order_by: [asc: s.position]
    )
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp filter_archive(query, :archived), do: from(d in query, where: not is_nil(d.archived_at))
  defp filter_archive(query, :all), do: query
  defp filter_archive(query, _filter), do: from(d in query, where: is_nil(d.archived_at))

  defp get_deal_by_slug(scope, slug) do
    Deal
    |> where(slug: ^slug, organization_id: ^scope.org.id)
    |> preload([:stage, :contact, :owner, :activities])
    |> Repo.one()
  end

  defp get_deal_by_id_param!(scope, value) do
    case Integer.parse(value) do
      {id, ""} -> get_deal!(scope, id)
      _ -> raise Ecto.NoResultsError, queryable: Deal
    end
  end

  defp maybe_record_stage_change(updated, old_deal, changeset, user_id) do
    if Ecto.Changeset.changed?(changeset, :stage_id) do
      %DealActivity{deal_id: updated.id, user_id: user_id}
      |> DealActivity.changeset(%{
        activity_type: :stage_change,
        old_value: to_string(old_deal.stage_id),
        new_value: to_string(updated.stage_id)
      })
      |> Repo.insert!()
    end
  end

  defp filter_by_contact(query, nil), do: query
  defp filter_by_contact(query, id), do: from(d in query, where: d.contact_id == ^id)

  defp filter_by_company(query, nil), do: query

  defp filter_by_company(query, id) do
    from(d in query,
      join: c in assoc(d, :contact),
      where: c.company_id == ^id
    )
  end

  defp filter_by_stage(query, nil), do: query
  defp filter_by_stage(query, id), do: from(d in query, where: d.stage_id == ^id)

  defp filter_by_stages(query, []), do: query
  defp filter_by_stages(query, ids), do: from(d in query, where: d.stage_id in ^ids)

  defp search_deals(query, nil), do: query
  defp search_deals(query, ""), do: query

  defp search_deals(query, search) do
    term = "%#{search}%"

    from(d in query,
      left_join: c in assoc(d, :contact),
      where:
        ilike(d.title, ^term) or ilike(c.first_name, ^term) or ilike(c.last_name, ^term) or
          ilike(c.email, ^term)
    )
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)

  defp deals_base_query(scope) do
    from(d in Deal, where: d.organization_id == ^scope.org.id)
  end

  defp filter_by_min_value(query, nil), do: query
  defp filter_by_min_value(query, value), do: from(d in query, where: d.value >= ^value)

  defp filter_by_min_probability(query, nil), do: query

  defp filter_by_min_probability(query, probability),
    do: from(d in query, where: d.probability >= ^probability)

  defp filter_by_close_from(query, nil), do: query

  defp filter_by_close_from(query, date),
    do: from(d in query, where: d.expected_close_date >= ^date)

  defp filter_by_close_to(query, nil), do: query

  defp filter_by_close_to(query, date),
    do: from(d in query, where: d.expected_close_date <= ^date)

  defp filter_by_sources(query, []), do: query
  defp filter_by_sources(query, sources), do: from(d in query, where: d.source in ^sources)

  defp sort_deals(query, :value, dir), do: from(d in query, order_by: [{^dir, d.value}])

  defp sort_deals(query, :expected_close_date, dir),
    do: from(d in query, order_by: [{^dir, d.expected_close_date}])

  defp sort_deals(query, _field, dir), do: from(d in query, order_by: [{^dir, d.inserted_at}])

  defp archive_attrs(scope, reason) do
    %{
      archived_at: DateTime.utc_now(:second),
      archived_by_id: scope.user.id,
      archive_reason: reason
    }
  end
end
