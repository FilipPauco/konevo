defmodule KonevoWeb.AutomationLive.IndexTest do
  use KonevoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Konevo.Factory
  import Konevo.MessagingFixtures

  alias Konevo.{Automation, Messaging}

  defp org_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}

  describe "automation screen" do
    setup :register_and_log_in_user_with_org

    test "renders configuration and approval tabs", %{conn: conn, org: org} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      assert has_element?(view, "#automation-screen")
      assert has_element?(view, "#automation-sequence-form")
      assert has_element?(view, "#workflow-builder")
      assert has_element?(view, "#workflow-builder-header")
      assert has_element?(view, "#workflow-card-no_reply_follow_up")
      assert has_element?(view, "#workflow-card-inbound_email_task")
      assert has_element?(view, "#automation-action-mode-select input.h-10.cursor-pointer")
      assert has_element?(view, "#sequence_mode-select-chevron")
      assert has_element?(view, "#sequence_idle_days[min='1']")
      assert has_element?(view, "#automation-workspace")
      assert has_element?(view, "#automation-tab-mobile-form")
      assert has_element?(view, "#automation-tab-mobile-select")

      assert has_element?(
               view,
               "#automation-tab-mobile-select input[name='automation_tab[tab_text_input]']"
             )

      assert has_element?(view, "#automation-tab-configuration.active")
      assert has_element?(view, "#automation-tab-task_suggestions")
      assert has_element?(view, "#automation-tab-email_drafts")
      refute has_element?(view, "#automation-tab-task-suggestions-count")
      refute has_element?(view, "#automation-tab-email-drafts-count")
      refute has_element?(view, "#automation-panel-configuration.hidden")
      assert has_element?(view, "#automation-panel-task-suggestions.hidden")
      assert has_element?(view, "#automation-panel-email-drafts.hidden")
      refute has_element?(view, "#task-approvals-loading")
      refute has_element?(view, "#drafts-loading")
    end

    test "switches between approval tabs", %{conn: conn, org: org} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      view
      |> element("#automation-tab-task_suggestions")
      |> render_click()

      assert has_element?(view, "#automation-tab-task_suggestions.active")
      refute has_element?(view, "#automation-panel-task-suggestions.hidden")
      assert has_element?(view, "#automation-panel-configuration.hidden")

      view
      |> element("#automation-tab-email_drafts")
      |> render_click()

      assert has_element?(view, "#automation-tab-email_drafts.active")
      refute has_element?(view, "#automation-panel-email-drafts.hidden")
    end

    test "switches tabs from the mobile picker", %{conn: conn, org: org} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      view
      |> render_hook("change_automation_tab", %{"automation_tab" => %{"tab" => "email_drafts"}})

      assert_patch(view, ~p"/automation?tab=email_drafts")
      refute has_element?(view, "#automation-panel-email-drafts.hidden")
    end

    test "keeps AI replies review-only while configuring a workflow", %{conn: conn, org: org} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      view
      |> element("#workflow-card-inbound_email_reply")
      |> render_click()

      assert has_element?(view, "#ai-reply-review-mode")
      refute has_element?(view, "#sequence_mode")
      refute render(view) =~ "Send AI reply automatically"
    end

    test "renders an action-mode Live Select for email-to-task workflows", %{conn: conn, org: org} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      view
      |> element("#workflow-card-inbound_email_task")
      |> render_click()

      assert has_element?(view, "#automation-action-mode-select input.h-10.cursor-pointer")
      assert has_element?(view, "#sequence_mode-select-chevron")
      refute has_element?(view, "#automation-sequence-form input[name='sequence[subject]']")
      refute has_element?(view, "#automation-sequence-form textarea[name='sequence[body]']")
    end

    test "opens an approval tab from its URL", %{conn: conn, org: org} do
      {:ok, view, _html} = live(org_conn(conn, org), "/automation?tab=email_drafts")
      _ = :sys.get_state(view.pid)

      assert has_element?(view, "#automation-tab-email_drafts.active")
      refute has_element?(view, "#automation-panel-email-drafts.hidden")
      assert has_element?(view, "#automation-panel-configuration.hidden")
    end

    test "paginates email drafts in groups of ten", %{conn: conn, org: org, scope: scope} do
      drafts = Enum.map(1..11, &draft_fixture(scope, %{body: "Draft #{&1}"}))

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      view
      |> element("#automation-tab-email_drafts")
      |> render_click()

      assert has_element?(view, "#drafts-pagination")
      assert has_element?(view, "#automation-tab-email-drafts-count", "11")

      first_page_ids =
        drafts
        |> Enum.filter(&has_element?(view, "#drafts-#{&1.id}"))
        |> Enum.map(& &1.id)

      assert length(first_page_ids) == 10

      view
      |> element("#drafts-pagination-next")
      |> render_click()

      second_page_ids =
        drafts
        |> Enum.filter(&has_element?(view, "#drafts-#{&1.id}"))
        |> Enum.map(& &1.id)

      assert length(second_page_ids) == 1
      assert MapSet.disjoint?(MapSet.new(first_page_ids), MapSet.new(second_page_ids))
    end

    test "shows the inbound sender for an unlinked draft", %{conn: conn, org: org, scope: scope} do
      thread = insert(:email_thread, organization: scope.org)

      insert(:email,
        organization: scope.org,
        thread: thread,
        from: "martin@example.com"
      )

      draft = draft_fixture(scope, %{email_thread: thread})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation?tab=email_drafts")
      _ = :sys.get_state(view.pid)

      assert has_element?(view, "#drafts-#{draft.id}", "martin@example.com")

      assert has_element?(
               view,
               "#draft-source-thread-#{draft.id}[href='/inbox/#{thread.id}']"
             )
    end

    test "returns an approved draft to review", %{conn: conn, org: org, scope: scope} do
      contact = insert(:contact, organization: scope.org, user: scope.user)
      draft = draft_fixture(scope, %{status: :approved, contact: contact})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation?tab=email_drafts")
      _ = :sys.get_state(view.pid)

      assert has_element?(view, "#unapprove-draft-#{draft.id}")

      view
      |> element("#unapprove-draft-#{draft.id}")
      |> render_click()

      assert Messaging.get_draft!(scope, draft.id).status == :pending
      assert has_element?(view, "#draft-approval-form-#{draft.id}")
    end

    test "creates a contact before returning an unlinked draft to review", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      thread = insert(:email_thread, organization: scope.org)

      insert(:email,
        organization: scope.org,
        thread: thread,
        from: "martin@example.com"
      )

      draft = draft_fixture(scope, %{status: :approved, email_thread: thread})

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation?tab=email_drafts")
      _ = :sys.get_state(view.pid)

      assert has_element?(view, "#create-draft-contact-#{draft.id}")
      refute has_element?(view, "#send-draft-#{draft.id}")

      view
      |> element("#create-draft-contact-#{draft.id}")
      |> render_click()

      updated_draft = Messaging.get_draft!(scope, draft.id)
      assert updated_draft.status == :pending
      assert updated_draft.contact_id
      assert has_element?(view, "#draft-approval-form-#{draft.id}")
    end

    test "clears every email draft from the review queue", %{conn: conn, org: org, scope: scope} do
      drafts = Enum.map(1..2, &draft_fixture(scope, %{body: "Draft #{&1}"}))

      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation?tab=email_drafts")
      _ = :sys.get_state(view.pid)

      assert has_element?(view, "#clear-all-drafts")

      view
      |> element("#clear-all-drafts")
      |> render_click()

      refute has_element?(view, "#clear-all-drafts")
      assert Enum.all?(drafts, &(Messaging.get_draft!(scope, &1.id).status == :rejected))
    end

    test "refreshes approvals when a background draft is created", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      draft = draft_fixture(scope, %{body: "Background draft"})
      send(view.pid, :automation_approvals_changed)

      assert has_element?(view, "#drafts-#{draft.id}")
    end

    test "creates a manual no-reply follow-up workflow with steps", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      refute has_element?(view, "#no-reply-global-ai-settings-hint")
      refute has_element?(view, "#automation-sequence-form textarea[name='sequence[body]']")

      view
      |> form("#automation-sequence-form", %{
        "sequence" => %{
          "name" => "Lead follow-up",
          "workflow_type" => "no_reply_follow_up",
          "mode" => "manual",
          "idle_days" => "2",
          "subject" => "Checking in",
          "excluded_senders" => "noreply@*"
        }
      })
      |> render_submit()

      assert has_element?(view, "#activate-sequence-button")
      assert has_element?(view, "#rules div[id^='rules-']")

      [sequence] = Automation.list_sequences(scope)
      rules = Automation.list_rules(sequence)

      assert sequence.trigger_config["mode"] == "manual"
      assert sequence.trigger_config["approval_required"]
      assert Enum.map(rules, & &1.action_type) == [:wait, :prepare_follow_up]
      [_, follow_up_rule] = rules
      refute Map.has_key?(follow_up_rule.action_config, "body")
    end

    test "creates an automatic no-reply follow-up workflow", %{conn: conn, org: org, scope: scope} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      render_submit(view, "save_sequence", %{
        "sequence" => %{
          "name" => "Automatic lead follow-up",
          "workflow_type" => "no_reply_follow_up",
          "mode" => "automatic",
          "idle_days" => "4",
          "subject" => "Still interested?",
          "excluded_senders" => "noreply@*"
        }
      })

      [sequence] = Automation.list_sequences(scope)
      [_, follow_up_rule] = Automation.list_rules(sequence)

      assert sequence.trigger_config["mode"] == "automatic"
      refute sequence.trigger_config["approval_required"]
      assert follow_up_rule.action_config["mode"] == "automatic"
      refute follow_up_rule.action_config["approval_required"]
    end

    test "hides create form while inspecting an existing workflow", %{conn: conn, org: org} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      view
      |> form("#automation-sequence-form", %{
        "sequence" => %{
          "name" => "Lead follow-up",
          "workflow_type" => "no_reply_follow_up",
          "mode" => "manual",
          "idle_days" => "2",
          "subject" => "Checking in",
          "excluded_senders" => "noreply@*"
        }
      })
      |> render_submit()

      refute has_element?(view, "#automation-sequence-form")
      assert has_element?(view, "#workflow-builder-header")
      assert has_element?(view, "#activate-sequence-button")

      view
      |> element("#workflow-card-inbound_email_task")
      |> render_click()

      assert has_element?(view, "#automation-sequence-form")
      refute has_element?(view, "#activate-sequence-button")
    end

    test "removes archived workflows from the active workflows list", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      view
      |> form("#automation-sequence-form", %{
        "sequence" => %{
          "name" => "Archived follow-up",
          "workflow_type" => "no_reply_follow_up",
          "mode" => "manual",
          "idle_days" => "2",
          "subject" => "Checking in",
          "excluded_senders" => "noreply@*"
        }
      })
      |> render_submit()

      view
      |> element("#archive-sequence-button")
      |> render_click()

      [sequence] = Automation.list_sequences(scope)
      assert sequence.status == :archived
      refute render(view) =~ "Archived follow-up"
      refute has_element?(view, "#archive-sequence-button")
    end

    test "creates an email-to-task workflow without task instructions", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      view
      |> element("#workflow-card-inbound_email_task")
      |> render_click()

      render_submit(view, "save_sequence", %{
        "sequence" => %{
          "name" => "Extract sales tasks",
          "workflow_type" => "inbound_email_task",
          "mode" => "automatic",
          "excluded_senders" => "noreply@*"
        }
      })

      [sequence] = Automation.list_sequences(scope)
      [rule] = Automation.list_rules(sequence)

      assert has_element?(view, "#rules div[id^='rules-']")
      assert sequence.trigger_config["mode"] == "automatic"
      refute sequence.trigger_config["approval_required"]
      assert rule.action_type == :prepare_task
      assert rule.action_config["mode"] == "automatic"
      refute Map.has_key?(rule.action_config, "title")
      refute Map.has_key?(rule.action_config, "instructions")
    end

    test "creates a manual email-to-task workflow", %{conn: conn, org: org, scope: scope} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      view
      |> element("#workflow-card-inbound_email_task")
      |> render_click()

      view
      |> form("#automation-sequence-form", %{
        "sequence" => %{
          "name" => "Review lead tasks",
          "workflow_type" => "inbound_email_task",
          "mode" => "manual",
          "excluded_senders" => "noreply@*"
        }
      })
      |> render_submit()

      [sequence] = Automation.list_sequences(scope)
      [rule] = Automation.list_rules(sequence)

      assert sequence.trigger_config["mode"] == "manual"
      assert sequence.trigger_config["approval_required"]
      assert rule.action_config["mode"] == "manual"
    end
  end

  describe "automation screen for members" do
    setup %{conn: conn} do
      KonevoWeb.ConnCase.register_and_log_in_user_with_org(%{conn: conn, role: :member})
    end

    test "can create rules and activate a workflow", %{conn: conn, org: org, scope: scope} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      view
      |> form("#automation-sequence-form", %{
        "sequence" => %{
          "name" => "Member follow-up",
          "workflow_type" => "no_reply_follow_up",
          "mode" => "manual",
          "idle_days" => "2",
          "subject" => "Checking in",
          "excluded_senders" => "noreply@*"
        }
      })
      |> render_submit()

      [sequence] = Automation.list_sequences(scope)
      assert length(Automation.list_rules(sequence)) == 2

      view
      |> element("#activate-sequence-button")
      |> render_click()

      assert Automation.get_sequence!(scope, sequence.id).status == :active
      refute render(view) =~ "You cannot update this workflow"
    end
  end

  describe "automation screen for viewers" do
    setup %{conn: conn} do
      KonevoWeb.ConnCase.register_and_log_in_user_with_org(%{conn: conn, role: :viewer})
    end

    test "hides workflow creation controls", %{conn: conn, org: org} do
      {:ok, view, _html} = live(org_conn(conn, org), ~p"/automation")
      _ = :sys.get_state(view.pid)

      refute has_element?(view, "#automation-sequence-form")
      refute has_element?(view, "#workflow-card-no_reply_follow_up")
      refute has_element?(view, "#workflow-card-inbound_email_task")
      refute has_element?(view, "#save-sequence-button")
    end
  end
end
