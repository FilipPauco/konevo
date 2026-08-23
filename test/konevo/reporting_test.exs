defmodule Konevo.ReportingTest do
  use Konevo.DataCase

  import Konevo.AccountsFixtures
  import Konevo.DealsFixtures
  import Konevo.InboxFixtures
  import Konevo.TasksFixtures

  alias Konevo.Reporting

  describe "dashboard/1" do
    test "summarizes owner attention, follow-up, pipeline, and task risk" do
      %{scope: scope} = user_with_org_fixture()
      now = DateTime.utc_now(:second)
      stage = deal_stage_fixture(scope)

      deal =
        deal_fixture(scope, stage, %{
          title: "Website redesign",
          value: Decimal.new("2500"),
          expected_close_date: Date.add(Date.utc_today(), 5),
          next_action_due_date: nil
        })

      thread_fixture(scope, %{
        subject: "Quote request",
        category: :lead,
        is_unresolved: true,
        revenue_at_risk: Decimal.new("5000"),
        last_inbound_at: DateTime.add(now, -4, :day),
        deal: deal
      })

      thread_fixture(scope, %{
        subject: "Billing question",
        category: :billing,
        is_unresolved: true,
        last_inbound_at: DateTime.add(now, -2, :day)
      })

      task_fixture(scope, %{
        title: "Send proposal",
        due_date: DateTime.add(now, -1, :day),
        priority: :high,
        deal: deal
      })

      assert {:ok, dashboard} = Reporting.dashboard(scope)

      assert dashboard.brief.needs_reply == 2
      assert Decimal.equal?(dashboard.brief.revenue_at_risk, Decimal.new("5000"))
      assert dashboard.brief.overdue_tasks == 1
      assert dashboard.brief.closing_this_week == 1

      assert dashboard.follow_up_radar.stale_3d == 1
      assert dashboard.follow_up_radar.high_value_quiet == 1
      assert dashboard.pipeline_risk.no_next_action == 1
      assert dashboard.task_commitments.overdue == 1

      assert Enum.any?(dashboard.action_queue, &(&1.type == :thread))
      assert Enum.any?(dashboard.action_queue, &(&1.type == :task))
      assert Enum.any?(dashboard.action_queue, &(&1.type == :deal))
    end

    test "rejects scopes without an organization" do
      assert {:error, :invalid_scope} = Reporting.dashboard(%{user: %{id: 1}})
    end
  end
end
