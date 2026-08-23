defmodule Konevo.Reporting do
  @moduledoc """
  Operational reporting for the owner dashboard.

  This context keeps the dashboard focused on money and follow-up risk rather
  than broad analytics.
  """

  import Ecto.Query, warn: false

  alias Konevo.Deals.{Deal, DealStage}
  alias Konevo.Inbox.EmailThread
  alias Konevo.Repo
  alias Konevo.Tasks.Task

  @attention_categories [:lead, :customer, :support, :billing]
  @revenue_categories [:lead, :customer]
  @active_task_statuses [:open, :in_progress]
  @action_queue_limit 10

  def dashboard(%{user: %{id: _user_id}, org: %{id: _org_id}} = scope) do
    now = DateTime.utc_now(:second)
    today = Date.utc_today()

    threads = attention_threads(scope, now, 10)
    overdue_tasks = overdue_tasks(scope, now, 8)
    closing_deals = closing_deals(scope, today, 14, 8)
    stale_deals = stale_deals(scope, now, 8)

    dashboard = %{
      brief: daily_owner_brief(scope, now, today),
      action_queue: action_queue(threads, overdue_tasks, closing_deals, stale_deals, now, today),
      follow_up_radar: follow_up_radar(scope, now),
      pipeline_risk: pipeline_risk(scope, now, today),
      task_commitments: task_commitments(scope, now, today)
    }

    {:ok, dashboard}
  end

  def dashboard(_scope), do: {:error, :invalid_scope}

  defp daily_owner_brief(scope, now, today) do
    needs_reply = unresolved_attention_count(scope)
    revenue_at_risk = revenue_at_risk(scope)
    overdue_tasks = overdue_task_count(scope, now)
    closing_this_week = closing_deal_count(scope, today, 7)

    %{
      needs_reply: needs_reply,
      revenue_at_risk: revenue_at_risk,
      overdue_tasks: overdue_tasks,
      closing_this_week: closing_this_week
    }
  end

  defp action_queue(threads, overdue_tasks, closing_deals, stale_deals, now, today) do
    thread_items = Enum.map(threads, &thread_queue_item(&1, now))
    task_items = Enum.map(overdue_tasks, &task_queue_item(&1, now))
    closing_items = Enum.map(closing_deals, &closing_deal_queue_item(&1, today))
    stale_items = Enum.map(stale_deals, &stale_deal_queue_item(&1, now))

    [thread_items, task_items, closing_items, stale_items]
    |> List.flatten()
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(@action_queue_limit)
  end

  defp follow_up_radar(scope, now) do
    %{
      stale_24h: stale_thread_count(scope, now, 1),
      stale_3d: stale_thread_count(scope, now, 3),
      stale_7d: stale_thread_count(scope, now, 7),
      high_value_quiet: high_value_quiet_count(scope, now),
      no_next_action: no_next_action_count(scope)
    }
  end

  defp pipeline_risk(scope, now, today) do
    month_end = Date.add(today, 30)

    %{
      closing_this_week: closing_deal_count(scope, today, 7),
      closing_this_month: closing_deal_count(scope, today, 30),
      closing_this_month_value: closing_deal_value(scope, today, month_end),
      overdue_next_actions: overdue_next_action_count(scope, now),
      no_next_action: no_next_action_count(scope),
      top_closing_deals: closing_deals(scope, today, 30, 5)
    }
  end

  defp task_commitments(scope, now, today) do
    tomorrow = Date.add(today, 1)
    week_end = Date.add(today, 7)

    %{
      overdue: overdue_task_count(scope, now),
      due_today: task_count_between(scope, today_start(today), today_start(tomorrow)),
      due_this_week: task_count_between(scope, today_start(today), today_start(week_end)),
      top_overdue: overdue_tasks(scope, now, 5)
    }
  end

  defp attention_threads(scope, now, limit) do
    EmailThread
    |> attention_thread_query(scope)
    |> order_by([t, d],
      desc:
        fragment(
          "COALESCE(?, ?, 0) * EXTRACT(EPOCH FROM (? - COALESCE(?, ?, ?))) / 86400",
          t.revenue_at_risk,
          d.value,
          ^now,
          t.last_inbound_at,
          t.last_activity_at,
          t.inserted_at
        ),
      desc: t.last_inbound_at
    )
    |> limit(^limit)
    |> preload([_t, d], [:contact, deal: d])
    |> Repo.all()
  end

  defp attention_thread_query(queryable, scope) do
    from(t in queryable,
      left_join: d in assoc(t, :deal),
      where: t.organization_id == ^scope.org.id,
      where: t.is_unresolved == true,
      where: t.is_archived == false,
      where: is_nil(t.trashed_at),
      where: t.category in ^@attention_categories
    )
  end

  defp unresolved_attention_count(scope) do
    EmailThread
    |> attention_thread_query(scope)
    |> Repo.aggregate(:count, :id)
  end

  defp revenue_at_risk(scope) do
    EmailThread
    |> attention_thread_query(scope)
    |> where([t, _d], t.category in ^@revenue_categories)
    |> select([t, d], coalesce(sum(coalesce(t.revenue_at_risk, d.value)), 0))
    |> Repo.one()
    |> decimal()
  end

  defp stale_thread_count(scope, now, days) do
    cutoff = DateTime.add(now, -days, :day)

    EmailThread
    |> attention_thread_query(scope)
    |> where([t, _d], t.category in ^@revenue_categories)
    |> where(
      [t, _d],
      fragment("COALESCE(?, ?, ?)", t.last_inbound_at, t.last_activity_at, t.inserted_at) <=
        ^cutoff
    )
    |> Repo.aggregate(:count, :id)
  end

  defp high_value_quiet_count(scope, now) do
    cutoff = DateTime.add(now, -3, :day)

    EmailThread
    |> attention_thread_query(scope)
    |> where([t, _d], t.category in ^@revenue_categories)
    |> where(
      [t, d],
      coalesce(coalesce(t.revenue_at_risk, d.value), ^Decimal.new("0")) >= ^Decimal.new("1000")
    )
    |> where(
      [t, _d],
      fragment("COALESCE(?, ?, ?)", t.last_inbound_at, t.last_activity_at, t.inserted_at) <=
        ^cutoff
    )
    |> Repo.aggregate(:count, :id)
  end

  defp overdue_tasks(scope, now, limit) do
    Task
    |> active_task_query(scope)
    |> where([t], t.due_date < ^now)
    |> order_by([t], asc: t.due_date, desc: t.priority, asc: t.id)
    |> limit(^limit)
    |> preload([:contact, :company, :deal, :assigned_to])
    |> Repo.all()
  end

  defp overdue_task_count(scope, now) do
    Task
    |> active_task_query(scope)
    |> where([t], t.due_date < ^now)
    |> Repo.aggregate(:count, :id)
  end

  defp task_count_between(scope, starts_at, ends_at) do
    Task
    |> active_task_query(scope)
    |> where([t], t.due_date >= ^starts_at and t.due_date < ^ends_at)
    |> Repo.aggregate(:count, :id)
  end

  defp active_task_query(queryable, scope) do
    from(t in queryable,
      where: t.organization_id == ^scope.org.id,
      where: is_nil(t.archived_at),
      where: t.status in ^@active_task_statuses
    )
  end

  defp closing_deals(scope, today, days, limit) do
    end_date = Date.add(today, days)

    Deal
    |> open_deal_query(scope)
    |> where([d, _s], not is_nil(d.expected_close_date))
    |> where([d, _s], d.expected_close_date >= ^today and d.expected_close_date <= ^end_date)
    |> order_by([d, _s], asc: d.expected_close_date, desc: d.value, asc: d.id)
    |> limit(^limit)
    |> preload([:stage, :owner, contact: :company])
    |> Repo.all()
  end

  defp stale_deals(scope, now, limit) do
    Deal
    |> open_deal_query(scope)
    |> where(
      [d, _s],
      is_nil(d.next_action_due_date) or d.next_action_due_date < ^now
    )
    |> order_by([d, _s], desc: d.value, asc: d.next_action_due_date, asc: d.id)
    |> limit(^limit)
    |> preload([:stage, :owner, contact: :company])
    |> Repo.all()
  end

  defp closing_deal_count(scope, today, days) do
    end_date = Date.add(today, days)

    Deal
    |> open_deal_query(scope)
    |> where([d, _s], not is_nil(d.expected_close_date))
    |> where([d, _s], d.expected_close_date >= ^today and d.expected_close_date <= ^end_date)
    |> Repo.aggregate(:count, :id)
  end

  defp closing_deal_value(scope, starts_on, ends_on) do
    Deal
    |> open_deal_query(scope)
    |> where([d, _s], not is_nil(d.expected_close_date))
    |> where([d, _s], d.expected_close_date >= ^starts_on and d.expected_close_date <= ^ends_on)
    |> select([d, _s], coalesce(sum(d.value), 0))
    |> Repo.one()
    |> decimal()
  end

  defp overdue_next_action_count(scope, now) do
    Deal
    |> open_deal_query(scope)
    |> where([d, _s], not is_nil(d.next_action_due_date) and d.next_action_due_date < ^now)
    |> Repo.aggregate(:count, :id)
  end

  defp no_next_action_count(scope) do
    Deal
    |> open_deal_query(scope)
    |> where([d, _s], is_nil(d.next_action_due_date))
    |> Repo.aggregate(:count, :id)
  end

  defp open_deal_query(queryable, scope) do
    from(d in queryable,
      left_join: s in DealStage,
      on: s.id == d.stage_id,
      where: d.organization_id == ^scope.org.id,
      where: is_nil(d.archived_at),
      where: is_nil(d.closed_at),
      where: is_nil(s.id) or s.is_final == false
    )
  end

  defp thread_queue_item(thread, now) do
    age_days =
      age_days(thread.last_inbound_at || thread.last_activity_at || thread.inserted_at, now)

    amount = thread_risk_amount(thread)

    %{
      type: :thread,
      id: thread.id,
      title: thread.subject,
      subtitle: contact_label(thread.contact) || participant_label(thread.participants),
      meta: "#{category_label(thread.category)} · #{age_days}d quiet",
      amount: amount,
      icon: "icon-[tabler--inbox]",
      tone: if(age_days >= 3, do: :danger, else: :warning),
      action: :reply,
      score: Decimal.to_float(amount) + age_days * 250 + category_score(thread.category)
    }
  end

  defp task_queue_item(task, now) do
    age_days = age_days(task.due_date, now)

    %{
      type: :task,
      id: task.id,
      title: task.title,
      subtitle: task_contact_label(task),
      meta: "Overdue #{age_days}d · #{priority_label(task.priority)}",
      amount: (task.deal && task.deal.value) || Decimal.new(0),
      icon: "icon-[tabler--checkbox]",
      tone: :danger,
      action: :complete,
      score: 700 + age_days * 180 + priority_score(task.priority)
    }
  end

  defp closing_deal_queue_item(deal, today) do
    days = Date.diff(deal.expected_close_date, today)

    %{
      type: :deal,
      id: deal.id,
      title: deal.title,
      subtitle: contact_label(deal.contact),
      meta: "Closes in #{days}d",
      amount: decimal(deal.value),
      icon: "icon-[tabler--briefcase]",
      tone: if(days <= 3, do: :warning, else: :info),
      action: :review,
      score: Decimal.to_float(decimal(deal.value)) + max(0, 14 - days) * 120
    }
  end

  defp stale_deal_queue_item(deal, now) do
    age_days =
      case deal.next_action_due_date do
        nil -> 7
        due_date -> age_days(due_date, now)
      end

    %{
      type: :deal,
      id: deal.id,
      title: deal.title,
      subtitle: contact_label(deal.contact),
      meta: stale_deal_meta(deal.next_action_due_date, age_days),
      amount: decimal(deal.value),
      icon: "icon-[tabler--target-arrow]",
      tone: :warning,
      action: :set_next_action,
      score: Decimal.to_float(decimal(deal.value)) + age_days * 160
    }
  end

  defp stale_deal_meta(nil, _age_days), do: "No next action"
  defp stale_deal_meta(_due_date, age_days), do: "Next action overdue #{age_days}d"

  defp thread_risk_amount(%{revenue_at_risk: %Decimal{} = value}), do: value
  defp thread_risk_amount(%{deal: %{value: %Decimal{} = value}}), do: value
  defp thread_risk_amount(_thread), do: Decimal.new(0)

  defp contact_label(%{first_name: first_name, last_name: last_name}) do
    [first_name, last_name]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> case do
      "" -> nil
      label -> label
    end
  end

  defp contact_label(_contact), do: nil

  defp participant_label([first | _]), do: first
  defp participant_label(_participants), do: "Unknown contact"

  defp task_contact_label(%{contact: contact, company: company}) do
    contact_label(contact) || company_label(company) || "Internal task"
  end

  defp company_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp company_label(_company), do: nil

  defp category_label(nil), do: "Uncategorised"
  defp category_label(category), do: category |> Atom.to_string() |> Phoenix.Naming.humanize()

  defp priority_label(priority), do: priority |> Atom.to_string() |> Phoenix.Naming.humanize()

  defp category_score(:lead), do: 800
  defp category_score(:customer), do: 700
  defp category_score(:support), do: 350
  defp category_score(:billing), do: 250
  defp category_score(_category), do: 0

  defp priority_score(:urgent), do: 600
  defp priority_score(:high), do: 400
  defp priority_score(:normal), do: 200
  defp priority_score(:low), do: 80
  defp priority_score(_priority), do: 0

  defp age_days(nil, _now), do: 0
  defp age_days(%DateTime{} = then, now), do: max(DateTime.diff(now, then, :day), 0)

  defp today_start(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value) when is_integer(value), do: Decimal.new(value)
  defp decimal(_value), do: Decimal.new(0)
end
