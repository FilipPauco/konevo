defmodule KonevoWeb.AutomationLive.Index do
  @moduledoc false

  use KonevoWeb, :live_view
  import LiveSelect

  alias Konevo.Automation
  alias Konevo.Messaging
  alias Konevo.Permissions

  @workflow_ids ~w(no_reply_follow_up inbound_email_task inbound_email_reply)
  @default_excluded_senders "noreply@*\nno-reply@*\ndonotreply@*\nnotification@*\n*@calendar.google.com"
  @approval_page_size 10

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, gettext("Workflows"))
      |> assign(:automation_tab, "configuration")
      |> assign(:automation_tab_form, automation_tab_form("configuration"))
      |> assign(:loading, true)
      |> assign(:active_sequence, nil)
      |> assign(:selected_workflow, "no_reply_follow_up")
      |> assign(:sequence_form, sequence_form("no_reply_follow_up"))
      |> assign(:can_create_workflow?, workflow_allowed?(socket, :create))
      |> assign(:can_update_workflow?, workflow_allowed?(socket, :update))
      |> assign(:draft_total, 0)
      |> assign(:draft_page, 1)
      |> assign(:draft_page_count, 1)
      |> assign(:draft_transition, nil)
      |> assign(:task_approval_total, 0)
      |> assign(:task_approval_page, 1)
      |> assign(:task_approval_page_count, 1)
      |> stream(:sequences, [])
      |> stream(:rules, [])
      |> stream(:drafts, [])
      |> stream(:task_approvals, [])

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Konevo.PubSub,
        approval_queue_topic(socket.assigns.current_scope.org.id)
      )

      send(self(), :load_automation)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    tab = automation_tab(Map.get(params, "tab"))

    {:noreply,
     socket
     |> assign(:automation_tab, tab)
     |> assign(:automation_tab_form, automation_tab_form(tab))}
  end

  @impl true
  def handle_info(:load_automation, socket) do
    {:noreply, load_automation(socket)}
  end

  def handle_info(:automation_approvals_changed, socket) do
    {:noreply, socket |> load_drafts() |> load_task_approvals()}
  end

  def handle_info({:refresh_drafts_after_transition, id}, socket) do
    transition = socket.assigns.draft_transition

    if transition && transition.id == id do
      {:noreply, socket |> assign(:draft_transition, nil) |> load_drafts()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("choose_workflow", %{"workflow" => workflow}, socket) do
    workflow = normalize_workflow(workflow)

    {:noreply,
     socket
     |> assign(:selected_workflow, workflow)
     |> assign(:sequence_form, sequence_form(workflow))
     |> assign(:active_sequence, nil)
     |> stream(:rules, [], reset: true)}
  end

  def handle_event("select_sequence", %{"id" => id}, socket) do
    {:noreply, select_sequence(socket, id)}
  end

  def handle_event("validate_sequence", %{"sequence" => params}, socket) do
    workflow = normalize_workflow(Map.get(params, "workflow_type"))

    {:noreply,
     socket
     |> assign(:selected_workflow, workflow)
     |> assign(:sequence_form, sequence_form(workflow, params))}
  end

  def handle_event("save_sequence", %{"sequence" => params}, socket) do
    scope = socket.assigns.current_scope
    attrs = clean_sequence_params(params)

    case Automation.create_sequence(scope, attrs) do
      {:ok, sequence} ->
        case create_workflow_rules(scope, sequence, params) do
          {:ok, _rules} ->
            {:noreply,
             socket
             |> put_flash(:success, gettext("Workflow created"))
             |> assign(:sequence_form, sequence_form(socket.assigns.selected_workflow))
             |> load_automation(sequence.id)}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, gettext("You cannot update this workflow"))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create workflow steps"))}
        end

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot create workflows"))}

      {:error, changeset} ->
        {:noreply, assign(socket, :sequence_form, to_form(changeset))}
    end
  end

  def handle_event("activate_sequence", %{"id" => id}, socket) do
    update_sequence_status(
      socket,
      id,
      &Automation.activate_sequence/2,
      gettext("Workflow activated")
    )
  end

  def handle_event("pause_sequence", %{"id" => id}, socket) do
    update_sequence_status(socket, id, &Automation.pause_sequence/2, gettext("Workflow paused"))
  end

  def handle_event("archive_sequence", %{"id" => id}, socket) do
    update_sequence_status(
      socket,
      id,
      &Automation.archive_sequence/2,
      gettext("Workflow archived")
    )
  end

  def handle_event("approve_draft", %{"_id" => id, "draft" => %{"body" => body}}, socket) do
    scope = socket.assigns.current_scope
    draft = Messaging.get_draft!(scope, id)

    case Messaging.approve_draft(scope, draft, body) do
      {:ok, _draft} ->
        {:noreply, begin_draft_transition(socket, id, :approve, gettext("Draft approved"))}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, gettext("Only pending drafts can be approved"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot approve drafts"))}
    end
  end

  def handle_event("reject_draft", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    draft = Messaging.get_draft!(scope, id)

    case Messaging.reject_draft(scope, draft) do
      {:ok, _draft} ->
        {:noreply, begin_draft_transition(socket, id, :reject, gettext("Draft rejected"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not reject draft"))}
    end
  end

  def handle_event("unapprove_draft", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    draft = Messaging.get_draft!(scope, id)

    case Messaging.unapprove_draft(scope, draft) do
      {:ok, _draft} ->
        {:noreply,
         socket |> put_flash(:info, gettext("Draft returned to review")) |> load_drafts()}

      {:error, :not_approved} ->
        {:noreply,
         put_flash(socket, :error, gettext("Only approved drafts can be returned to review"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update drafts"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not return the draft to review"))}
    end
  end

  def handle_event("create_draft_contact", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    draft = Messaging.get_draft!(scope, id)

    case Messaging.create_contact_and_unapprove_draft(scope, draft) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Contact linked; draft returned to review"))
         |> load_drafts()}

      {:error, :missing_sender} ->
        {:noreply,
         put_flash(socket, :error, gettext("Could not find an inbound sender for this draft"))}

      {:error, :missing_thread} ->
        {:noreply,
         put_flash(socket, :error, gettext("Could not find the source thread for this draft"))}

      {:error, :not_approved} ->
        {:noreply,
         put_flash(socket, :error, gettext("Only approved drafts can be returned to review"))}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You cannot create contacts or update drafts"))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, gettext("Could not create a contact for this draft"))}
    end
  end

  def handle_event("clear_all_drafts", _params, socket) do
    case Messaging.reject_all_review_drafts(socket.assigns.current_scope) do
      {:ok, _count} ->
        {:noreply,
         socket
         |> assign(:draft_page, 1)
         |> assign(:draft_transition, nil)
         |> put_flash(:info, gettext("Email drafts cleared"))
         |> load_drafts()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot clear email drafts"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not clear email drafts"))}
    end
  end

  def handle_event("send_draft", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    draft = Messaging.get_draft!(scope, id)

    case Messaging.send_approved_draft(scope, draft, require_consent?: false) do
      {:ok, _draft} ->
        {:noreply, socket |> put_flash(:success, gettext("Draft sent")) |> load_drafts()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, send_block_reason(reason))}
    end
  end

  def handle_event("change_draft_page", %{"page" => page}, socket) do
    {:noreply, socket |> assign(:draft_page, approval_page(page)) |> load_drafts()}
  end

  def handle_event("change_task_approval_page", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:task_approval_page, approval_page(page))
     |> load_task_approvals()}
  end

  def handle_event("approve_task_approval", %{"_id" => id, "task_approval" => params}, socket) do
    scope = socket.assigns.current_scope
    approval = Automation.get_task_approval!(scope, id)

    case Automation.approve_task_approval(scope, approval, params) do
      {:ok, _task} ->
        {:noreply,
         socket |> put_flash(:success, gettext("Task created")) |> load_task_approvals()}

      {:error, :not_pending} ->
        {:noreply,
         put_flash(socket, :error, gettext("Only pending task approvals can be created"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot approve tasks"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not create task"))}
    end
  end

  def handle_event("reject_task_approval", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    approval = Automation.get_task_approval!(scope, id)

    case Automation.reject_task_approval(scope, approval) do
      {:ok, _approval} ->
        {:noreply,
         socket |> put_flash(:info, gettext("Task approval rejected")) |> load_task_approvals()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not reject task approval"))}
    end
  end

  def handle_event("clear_all_task_approvals", _params, socket) do
    case Automation.reject_all_task_approvals(socket.assigns.current_scope) do
      {:ok, _count} ->
        {:noreply,
         socket
         |> assign(:task_approval_page, 1)
         |> put_flash(:info, gettext("Task suggestions cleared"))
         |> load_task_approvals()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot clear task suggestions"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not clear task suggestions"))}
    end
  end

  def handle_event("change_automation_tab", %{"automation_tab" => %{"tab" => tab}}, socket) do
    if Enum.any?(automation_tabs(), &(&1.id == tab)) do
      {:noreply, push_patch(socket, to: ~p"/automation?tab=#{tab}")}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "live_select_change",
        %{"id" => "automation-tab-mobile-select", "text" => text},
        socket
      ) do
    send_update(LiveSelect.Component,
      id: "automation-tab-mobile-select",
      options: automation_tab_options(text)
    )

    {:noreply, socket}
  end

  def handle_event(
        "live_select_change",
        %{"id" => "automation-action-mode-select", "text" => text},
        socket
      ) do
    send_update(LiveSelect.Component,
      id: "automation-action-mode-select",
      options: mode_select_options(socket.assigns.selected_workflow, text)
    )

    {:noreply, socket}
  end

  def handle_event(
        "live_select_change",
        %{"id" => "task-approval-priority-" <> _approval_id, "text" => text} = params,
        socket
      ) do
    send_update(LiveSelect.Component,
      id: params["id"],
      options: filter_task_priority_live_options(text)
    )

    {:noreply, socket}
  end

  defp load_automation(socket, selected_id \\ nil) do
    scope = socket.assigns.current_scope
    sequences = Enum.reject(Automation.list_sequences(scope), &(&1.status == :archived))
    selected_id = selected_id || selected_sequence_id(socket, sequences)
    selected_id = if Enum.any?(sequences, &(&1.id == selected_id)), do: selected_id, else: nil

    socket
    |> assign(:loading, false)
    |> stream(:sequences, sequences, reset: true)
    |> select_sequence(selected_id)
    |> load_drafts()
    |> load_task_approvals()
  end

  defp load_drafts(socket) do
    {drafts, total, page} =
      paged_approval_records(
        fn page ->
          Messaging.list_drafts(socket.assigns.current_scope,
            status: [:pending, :approved],
            page: page,
            per_page: @approval_page_size
          )
        end,
        socket.assigns.draft_page
      )

    socket
    |> assign(:draft_total, total)
    |> assign(:draft_page, page)
    |> assign(:draft_page_count, approval_page_count(total))
    |> stream(:drafts, drafts, reset: true)
  end

  defp begin_draft_transition(socket, id, action, message) do
    Process.send_after(self(), {:refresh_drafts_after_transition, id}, 220)

    socket
    |> assign(:draft_transition, %{id: id, action: action})
    |> put_flash(if(action == :approve, do: :success, else: :info), message)
  end

  defp load_task_approvals(socket) do
    {approvals, total, page} =
      paged_approval_records(
        fn page ->
          Automation.list_task_approvals(socket.assigns.current_scope,
            status: :pending,
            page: page,
            per_page: @approval_page_size
          )
        end,
        socket.assigns.task_approval_page
      )

    socket
    |> assign(:task_approval_total, total)
    |> assign(:task_approval_page, page)
    |> assign(:task_approval_page_count, approval_page_count(total))
    |> stream(:task_approvals, approvals, reset: true)
  end

  defp paged_approval_records(fetch_page, requested_page) do
    {records, total} = fetch_page.(requested_page)
    page = min(requested_page, approval_page_count(total))

    if page == requested_page do
      {records, total, page}
    else
      {records, total} = fetch_page.(page)
      {records, total, page}
    end
  end

  defp approval_page(value) when is_integer(value), do: max(value, 1)

  defp approval_page(value) do
    case Integer.parse(to_string(value)) do
      {page, ""} -> approval_page(page)
      _ -> 1
    end
  end

  defp approval_page_count(total),
    do: max(div(total + @approval_page_size - 1, @approval_page_size), 1)

  defp approval_queue_topic(org_id), do: "automation:approvals:#{org_id}"

  defp select_sequence(socket, nil) do
    socket
    |> assign(:active_sequence, nil)
    |> stream(:rules, [], reset: true)
  end

  defp select_sequence(socket, id) do
    sequence = Automation.get_sequence_with_rules!(socket.assigns.current_scope, id)

    socket
    |> assign(:active_sequence, sequence)
    |> assign(:selected_workflow, nil)
    |> stream(:rules, sequence.rules, reset: true)
  end

  defp selected_sequence_id(socket, sequences) do
    cond do
      socket.assigns.active_sequence &&
          Enum.any?(sequences, &(&1.id == socket.assigns.active_sequence.id)) ->
        socket.assigns.active_sequence.id

      sequences != [] ->
        sequences |> List.first() |> Map.get(:id)

      true ->
        nil
    end
  end

  defp update_sequence_status(socket, id, fun, message) do
    scope = socket.assigns.current_scope
    sequence = Automation.get_sequence!(scope, id)

    case fun.(scope, sequence) do
      {:ok, sequence} ->
        {:noreply, socket |> put_flash(:success, message) |> load_automation(sequence.id)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update this workflow"))}

      {:error, :workflow_type_already_active} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Only one workflow of this type can be active at a time.")
         )}
    end
  end

  defp sequence_form(workflow, attrs \\ %{}) do
    workflow
    |> default_sequence_attrs()
    |> Map.merge(attrs)
    |> to_form(as: :sequence)
  end

  defp default_sequence_attrs("inbound_email_task") do
    %{
      "workflow_type" => "inbound_email_task",
      "name" => gettext("Create tasks from lead emails"),
      "mode" => "manual",
      "idle_days" => "1",
      "excluded_senders" => @default_excluded_senders
    }
  end

  defp default_sequence_attrs("inbound_email_reply") do
    %{
      "workflow_type" => "inbound_email_reply",
      "name" => gettext("AI reply to incoming emails"),
      "mode" => "manual",
      "idle_days" => "1",
      "subject" => "",
      "body" => "",
      "excluded_senders" => @default_excluded_senders
    }
  end

  defp default_sequence_attrs(_workflow) do
    %{
      "workflow_type" => "no_reply_follow_up",
      "name" => gettext("No-reply follow-up"),
      "mode" => "manual",
      "idle_days" => "3",
      "subject" => gettext("Following up"),
      "excluded_senders" => @default_excluded_senders
    }
  end

  defp clean_sequence_params(params) do
    workflow = normalize_workflow(Map.get(params, "workflow_type"))

    %{
      "name" => Map.get(params, "name"),
      "description" => workflow_description(workflow, params),
      "trigger_type" => workflow_trigger(workflow),
      "trigger_config" => trigger_config(workflow, params)
    }
  end

  defp trigger_config(workflow, params) do
    %{
      "workflow_type" => workflow,
      "mode" => workflow_mode(workflow, params),
      "idle_days" => normalize_days(Map.get(params, "idle_days")),
      "excluded_senders" => excluded_senders(params),
      "stop_on_inbound_reply" => workflow == "no_reply_follow_up",
      "approval_required" => workflow_mode(workflow, params) == "manual"
    }
  end

  defp create_workflow_rules(scope, sequence, params) do
    workflow = normalize_workflow(Map.get(params, "workflow_type"))

    workflow
    |> workflow_rules(params)
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, rules} ->
      case Automation.add_rule(scope, sequence, attrs) do
        {:ok, rule} -> {:cont, {:ok, [rule | rules]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp workflow_rules("inbound_email_task", params) do
    [
      %{
        "action_type" => "prepare_task",
        "delay_seconds" => 0,
        "action_config" => %{
          "mode" => Map.get(params, "mode", "manual"),
          "ai_generated" => true
        }
      }
    ]
  end

  defp workflow_rules("inbound_email_reply", params) do
    [
      %{
        "action_type" => "prepare_reply",
        "delay_seconds" => 0,
        "action_config" => %{
          "mode" => workflow_mode("inbound_email_reply", params),
          "ai_generated" => true
        }
      }
    ]
  end

  defp workflow_rules(_workflow, params) do
    days = normalize_days(Map.get(params, "idle_days"))

    [
      %{"action_type" => "wait", "delay_seconds" => follow_up_delay_seconds(days)},
      %{
        "action_type" => "prepare_follow_up",
        "delay_seconds" => 0,
        "action_config" => %{
          "subject" => Map.get(params, "subject", gettext("Following up")),
          "mode" => Map.get(params, "mode", "manual"),
          "approval_required" => Map.get(params, "mode", "manual") == "manual"
        }
      }
    ]
  end

  defp normalize_workflow(workflow) when workflow in @workflow_ids, do: workflow
  defp normalize_workflow(_workflow), do: "no_reply_follow_up"

  defp workflow_mode("inbound_email_reply", _params), do: "manual"
  defp workflow_mode(_workflow, params), do: Map.get(params, "mode", "manual")

  defp workflow_trigger("inbound_email_task"), do: "inbound_email_received"
  defp workflow_trigger("inbound_email_reply"), do: "inbound_email_received"
  defp workflow_trigger(_workflow), do: "inbound_email_idle"

  defp workflow_description("inbound_email_task", _params) do
    gettext("When a lead email arrives, AI prepares a task for review or automatic creation.")
  end

  defp workflow_description("inbound_email_reply", _params) do
    gettext("When an email arrives, AI writes a reply based on the email thread.")
  end

  defp workflow_description(_workflow, params) do
    days = normalize_days(Map.get(params, "idle_days"))
    gettext("After %{days} days without a customer reply, prepare a follow-up.", days: days)
  end

  defp workflow_display_description(sequence), do: sequence.description

  defp excluded_senders(params) do
    params
    |> Map.get("excluded_senders", "")
    |> String.split(~r/[\n,]+/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_days(days) do
    case Integer.parse(to_string(days)) do
      {days, ""} when days >= 1 -> days
      _ -> 1
    end
  end

  defp follow_up_delay_seconds(days), do: days * 86_400

  defp send_block_reason(:suppressed), do: gettext("Send blocked: contact is suppressed")
  defp send_block_reason(:no_consent), do: gettext("Send blocked: consent is missing")
  defp send_block_reason(:no_address), do: gettext("Send blocked: no sendable address")
  defp send_block_reason(:no_contact), do: gettext("Send blocked: draft has no contact")
  defp send_block_reason(:not_approved), do: gettext("Approve the draft before sending")
  defp send_block_reason(_reason), do: gettext("Send blocked by compliance checks")

  defp workflow_allowed?(socket, action) do
    case socket.assigns.current_scope do
      %{membership: %Konevo.Accounts.Membership{} = membership} ->
        Permissions.can?(membership, :automation, action)

      _scope ->
        false
    end
  end

  defp workflow_cards(assigns) do
    [
      %{
        id: "no_reply_follow_up",
        icon: "icon-[tabler--mail-forward]",
        name: gettext("No-reply follow-up"),
        summary: gettext("Your sent email has no customer reply after N days."),
        result:
          gettext(
            "AI prepares a follow-up using your global preferences; send only after approval unless set automatic."
          )
      },
      %{
        id: "inbound_email_task",
        icon: "icon-[tabler--checkbox]",
        name: gettext("Email to task"),
        summary: gettext("A new lead email arrives."),
        result: gettext("AI creates tasks directly, or queues extracted tasks for approval.")
      },
      %{
        id: "inbound_email_reply",
        icon: "icon-[tabler--sparkles]",
        name: gettext("AI email reply"),
        summary: gettext("A new customer email arrives."),
        result: gettext("AI drafts a contextual reply for your review.")
      }
    ]
    |> Enum.map(&Map.put(&1, :active?, &1.id == assigns.selected_workflow))
  end

  defp automation_tabs do
    [
      %{id: "configuration", label: gettext("Configuration"), icon: "icon-[tabler--settings]"},
      %{
        id: "task_suggestions",
        label: gettext("Task suggestions"),
        icon: "icon-[tabler--checkbox]"
      },
      %{id: "email_drafts", label: gettext("Email drafts"), icon: "icon-[tabler--mail]"}
    ]
  end

  defp automation_tab_form(tab), do: to_form(%{"tab" => tab}, as: "automation_tab")

  defp automation_tab_options(query \\ "") do
    normalized_query = query |> String.trim() |> String.downcase()

    automation_tabs()
    |> Enum.filter(fn tab ->
      normalized_query == "" or String.contains?(String.downcase(tab.label), normalized_query)
    end)
    |> Enum.map(fn tab -> %{label: tab.label, value: tab.id} end)
  end

  defp automation_tab_icon(tab_id) do
    automation_tabs()
    |> Enum.find(%{icon: "icon-[tabler--settings]"}, &(&1.id == tab_id))
    |> Map.fetch!(:icon)
  end

  defp automation_tab(tab) do
    if Enum.any?(automation_tabs(), &(&1.id == tab)), do: tab, else: "configuration"
  end

  defp choose_workflow_js(workflow) do
    active_class = "border-primary/45 bg-primary/8 shadow-sm shadow-primary/10"

    @workflow_ids
    |> Enum.reduce(JS.push("choose_workflow", value: %{workflow: workflow}), fn id, js ->
      JS.remove_class(js, active_class, to: "#workflow-card-#{id}")
    end)
    |> JS.add_class(active_class, to: "#workflow-card-#{workflow}")
  end

  defp mode_label("automatic"), do: gettext("Automatic")
  defp mode_label(_mode), do: gettext("Needs approval")

  defp mode_options("inbound_email_task") do
    [
      {gettext("Review extracted tasks"), "manual"},
      {gettext("Create extracted tasks"), "automatic"}
    ]
  end

  defp mode_options(_workflow) do
    [
      {gettext("Needs approval"), "manual"},
      {gettext("Automatic"), "automatic"}
    ]
  end

  defp mode_select_options(workflow, query \\ "") do
    normalized_query = query |> to_string() |> String.trim() |> String.downcase()

    workflow
    |> mode_options()
    |> Enum.map(fn {label, value} ->
      %{label: label, value: value, icon: action_mode_icon(value)}
    end)
    |> Enum.filter(fn option ->
      normalized_query == "" || String.contains?(String.downcase(option.label), normalized_query)
    end)
  end

  defp action_mode_icon("automatic"), do: "icon-[tabler--bolt]"
  defp action_mode_icon(_mode), do: "icon-[tabler--eye]"

  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:workflow, :string, required: true)

  defp action_mode_select(assigns) do
    options = mode_select_options(assigns.workflow)
    selected_option = Enum.find(options, &(&1.value == to_string(assigns.field.value || "")))

    assigns =
      assigns
      |> assign(:options, options)
      |> assign(:selected_option, selected_option)

    ~H"""
    <div class="fieldset flex w-full flex-col gap-2">
      <span id={"#{@field.id}-label"} class="label">{gettext("Action mode")}</span>
      <div class="group relative w-full">
        <span class="pointer-events-none absolute inset-y-0 left-3 z-20 flex items-center">
          <span class="flex size-6 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
            <.icon name={action_mode_icon(@field.value)} class="size-3.5" />
          </span>
        </span>
        <.live_select
          field={@field}
          id="automation-action-mode-select"
          options={@options}
          value={@selected_option || @field.value}
          value_mapper={&action_mode_option_value(&1, @options)}
          placeholder={gettext("Choose action mode")}
          style={:none}
          debounce={120}
          update_min_len={0}
          container_class="relative w-full"
          text_input_class="input h-10 w-full cursor-pointer pl-11 pr-12 font-medium placeholder:text-base-content/40 focus:cursor-text"
          dropdown_class="absolute left-0 top-[calc(100%+4px)] z-[300] max-h-60 w-full overflow-y-auto rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-xl shadow-base-content/10"
          option_class="flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-sm"
          available_option_class="cursor-pointer rounded-md hover:bg-base-200/70"
          selected_option_class="cursor-pointer rounded-md bg-base-200/70 font-semibold"
          active_option_class="bg-base-200"
        >
          <:option :let={option}>
            <span class="flex size-6 shrink-0 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
              <.icon name={option.icon} class="size-3" />
            </span>
            <span class="min-w-0 flex-1 truncate">{option.label}</span>
          </:option>
        </.live_select>
        <span
          id={"#{@field.id}-select-chevron"}
          class="pointer-events-none absolute inset-y-0 right-2 z-20 flex items-center text-base-content/45"
        >
          <.icon
            name="icon-[tabler--chevron-down]"
            class="size-4 transition-transform duration-200 group-focus-within:rotate-180"
          />
        </span>
      </div>
    </div>
    """
  end

  defp action_mode_option_value(value, options) when is_binary(value) do
    case Enum.find(options, &(to_string(&1.value) == value)) do
      nil -> value
      option -> option.value
    end
  end

  defp action_mode_option_value(value, _options), do: value

  attr :status, :atom, required: true

  defp workflow_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-semibold",
      status_pill_class(@status)
    ]}>
      <.icon name={status_icon(@status)} class="size-3.5" />
      {Phoenix.Naming.humanize(@status)}
    </span>
    """
  end

  defp status_pill_class(:active), do: "border-primary/30 bg-primary/12 text-primary"
  defp status_pill_class(:paused), do: "border-warning/30 bg-warning/12 text-warning"
  defp status_pill_class(:archived), do: "border-base-content/15 bg-base-200 text-base-content/60"
  defp status_pill_class(_status), do: "border-base-content/15 bg-base-200 text-base-content/60"

  defp status_icon(:active), do: "icon-[tabler--player-play]"
  defp status_icon(:paused), do: "icon-[tabler--player-pause]"
  defp status_icon(:archived), do: "icon-[tabler--archive]"
  defp status_icon(_status), do: "icon-[tabler--circle]"

  defp rule_icon(:prepare_follow_up), do: "icon-[tabler--mail-forward]"
  defp rule_icon(:prepare_task), do: "icon-[tabler--checkbox]"
  defp rule_icon(:prepare_reply), do: "icon-[tabler--sparkles]"
  defp rule_icon(:wait), do: "icon-[tabler--clock]"
  defp rule_icon(_action_type), do: "icon-[tabler--bolt]"

  defp rule_label(:prepare_follow_up), do: gettext("Prepare follow-up")
  defp rule_label(:prepare_task), do: gettext("Prepare task with AI")
  defp rule_label(:prepare_reply), do: gettext("Prepare reply with AI")
  defp rule_label(:wait), do: gettext("Wait")
  defp rule_label(action_type), do: action_type |> Atom.to_string() |> Phoenix.Naming.humanize()

  defp display_rule_delay(%{delay_seconds: seconds}), do: seconds

  defp rule_summary(%{action_type: :prepare_task, action_config: config}) do
    [
      Map.get(config || %{}, "title"),
      Map.get(config || %{}, "instructions")
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" · ")
    |> present_or(gettext("Configured task extraction"))
  end

  defp rule_summary(%{action_type: :prepare_reply}) do
    gettext("Generated from the email thread")
  end

  defp rule_summary(%{action_config: config}) do
    Map.get(config || %{}, "subject") ||
      Map.get(config || %{}, "title") ||
      gettext("Configured step")
  end

  defp trigger_label(:inbound_email_received), do: gettext("Email arrives")
  defp trigger_label(:inbound_email_idle), do: gettext("No reply after delay")
  defp trigger_label(:new_lead_email), do: gettext("New lead email")

  defp trigger_label(trigger_type),
    do: trigger_type |> Atom.to_string() |> Phoenix.Naming.humanize()

  attr :seconds, :integer, required: true

  defp rule_delay(assigns) do
    ~H"""
    <%= if @seconds == 0 do %>
      <span class="tooltip tooltip-right" data-tip={gettext("Runs immediately")}>
        <span
          tabindex="0"
          role="img"
          aria-label={gettext("Runs immediately")}
          class="inline-flex text-base-content/35 transition-colors hover:text-primary focus:text-primary"
        >
          <.icon name="icon-[tabler--info-circle]" class="size-4" />
        </span>
      </span>
    <% else %>
      <span class="badge badge-sm badge-ghost rounded-md px-2.5">
        {delay_label(@seconds)}
      </span>
    <% end %>
    """
  end

  defp delay_label(seconds) when seconds < 3_600 do
    minutes = div(seconds, 60)
    ngettext("after 1 minute", "after %{count} minutes", minutes)
  end

  defp delay_label(seconds) do
    days = div(seconds, 86_400)
    ngettext("after 1 day", "after %{count} days", days)
  end

  defp sequence_mode(%{trigger_config: %{"workflow_type" => "inbound_email_reply"}}), do: "manual"

  defp sequence_mode(sequence) do
    get_in(sequence.trigger_config || %{}, ["mode"]) || "manual"
  end

  defp sequence_excluded_senders(sequence) do
    sequence_excluded_sender_patterns(sequence)
    |> Enum.join(", ")
  end

  defp sequence_excluded_sender_patterns(sequence) do
    (sequence.trigger_config || %{})
    |> Map.get("excluded_senders", [])
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
  end

  defp excluded_senders_preview(sequence) do
    case sequence_excluded_sender_patterns(sequence) do
      [] ->
        gettext("No ignored senders")

      [sender] ->
        sender

      [sender | rest] ->
        gettext("%{sender} and %{count} more", sender: sender, count: length(rest))
    end
  end

  defp draft_contact_label(%{contact: %{first_name: first, last_name: last, email: email}}) do
    [first, last]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> case do
      "" -> email || gettext("Unknown contact")
      name -> name
    end
  end

  defp draft_contact_label(%{source_email: %{from: from}}) when is_binary(from) and from != "",
    do: from

  defp draft_contact_label(%{email_thread: %{emails: emails}}) when is_list(emails) do
    emails
    |> Enum.filter(& &1.is_inbound)
    |> Enum.max_by(& &1.received_at, DateTime, fn -> nil end)
    |> case do
      %{from: from} when is_binary(from) and from != "" -> from
      _ -> gettext("Unknown contact")
    end
  end

  defp draft_contact_label(_draft), do: gettext("Unknown contact")

  attr(:id, :string, required: true)
  attr(:thread_id, :integer, required: true)

  defp source_thread_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={~p"/inbox/#{@thread_id}"}
      class="inline-flex items-center gap-1 text-xs font-medium text-primary transition-colors hover:text-primary/75"
    >
      <.icon name="icon-[tabler--arrow-up-right]" class="size-3.5" />
      {gettext("View source email")}
    </.link>
    """
  end

  defp draft_transition_action(nil, _draft_id), do: nil

  defp draft_transition_action(%{id: id, action: action}, draft_id) do
    if to_string(id) == to_string(draft_id), do: action
  end

  defp draft_transition_action(_transition, _draft_id), do: nil

  defp task_approval_form(approval) do
    %{
      "title" => approval.title,
      "description" => approval.description || "",
      "due_date" => task_approval_due_value(approval.due_date),
      "priority" => task_priority_value(approval.priority)
    }
    |> to_form(as: :task_approval)
  end

  defp task_approval_contact_label(%{
         contact: %{first_name: first, last_name: last, email: email}
       }) do
    [first, last]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> case do
      "" -> email || gettext("Unknown contact")
      name -> name
    end
  end

  defp task_approval_contact_label(%{email: %{from: from}}) when is_binary(from), do: from
  defp task_approval_contact_label(_approval), do: gettext("Unknown contact")

  defp task_approval_source_label(%{email_thread: %{subject: subject}}) when is_binary(subject),
    do: subject

  defp task_approval_source_label(%{email: %{subject: subject}}) when is_binary(subject),
    do: subject

  defp task_approval_source_label(_approval), do: gettext("Inbound email")

  defp task_approval_due_value(%DateTime{} = due_date) do
    due_date
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  defp task_approval_due_value(_due_date), do: ""

  defp task_priority_live_options do
    [
      %{
        label: gettext("Low"),
        value: "low",
        icon: "icon-[tabler--flag-filled]",
        color: "#94a3b8"
      },
      %{
        label: gettext("Normal"),
        value: "normal",
        icon: "icon-[tabler--flag-filled]",
        color: "#3b82f6"
      },
      %{
        label: gettext("High"),
        value: "high",
        icon: "icon-[tabler--flag-filled]",
        color: "#f97316"
      },
      %{
        label: gettext("Urgent"),
        value: "urgent",
        icon: "icon-[tabler--flag-filled]",
        color: "#ef4444"
      }
    ]
  end

  defp filter_task_priority_live_options(text) do
    query = text |> to_string() |> String.trim() |> String.downcase()

    Enum.filter(task_priority_live_options(), fn option ->
      String.contains?(String.downcase(option.label), query)
    end)
  end

  defp task_priority_icon_style(%{color: color}) do
    [
      "color: #{color}",
      "background-color: color-mix(in srgb, #{color} 12%, transparent)",
      "border-color: color-mix(in srgb, #{color} 24%, transparent)"
    ]
    |> Enum.join("; ")
  end

  defp task_priority_icon_style(_option), do: nil

  defp task_priority_live_value(value, options) when is_binary(value) do
    case Enum.find(options, &(to_string(&1.value) == value)) do
      nil -> value
      option -> option.value
    end
  end

  defp task_priority_live_value(value, _options), do: value

  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:id, :string, required: true)

  defp task_approval_priority_select(assigns) do
    options = task_priority_live_options()

    selected_option =
      Enum.find(options, &(&1.value == to_string(assigns.field.value || ""))) ||
        List.first(options)

    assigns = assigns |> assign(:options, options) |> assign(:selected_option, selected_option)

    ~H"""
    <div class="fieldset flex w-full flex-col gap-2">
      <span class="label">{gettext("Priority")}</span>
      <div class="group relative w-full">
        <span class="pointer-events-none absolute inset-y-0 left-3 z-20 flex items-center">
          <span
            id={"#{@id}-select-icon"}
            class="flex size-6 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70"
            style={task_priority_icon_style(@selected_option)}
          >
            <.icon name={@selected_option.icon} class="size-3.5" />
          </span>
        </span>
        <.live_select
          field={@field}
          id={@id}
          options={@options}
          value={@selected_option}
          value_mapper={&task_priority_live_value(&1, @options)}
          placeholder={gettext("Choose priority")}
          allow_clear={false}
          style={:none}
          debounce={120}
          update_min_len={0}
          container_class="relative w-full"
          text_input_class="input w-full cursor-pointer pl-11 pr-12 font-medium placeholder:text-base-content/40 focus:cursor-text"
          dropdown_class="absolute left-0 top-[calc(100%+4px)] z-[300] max-h-60 w-full overflow-y-auto rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-xl shadow-base-content/10"
          option_class="flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-sm"
          available_option_class="cursor-pointer rounded-md hover:bg-base-200/70"
          selected_option_class="cursor-pointer rounded-md bg-base-200/70 font-semibold"
          active_option_class="bg-base-200"
        >
          <:option :let={option}>
            <span
              class="flex size-6 shrink-0 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70"
              style={task_priority_icon_style(option)}
            >
              <.icon name={option.icon} class="size-3" />
            </span>
            <span class="min-w-0 flex-1 truncate">{option.label}</span>
            <.icon
              :if={option.selected}
              name="icon-[tabler--check]"
              class="size-3.5 shrink-0 text-primary"
            />
          </:option>
        </.live_select>
        <span
          id={"#{@id}-select-chevron"}
          class="pointer-events-none absolute inset-y-0 right-2 z-20 flex items-center text-base-content/45"
        >
          <.icon
            name="icon-[tabler--chevron-down]"
            class="size-4 transition-transform duration-200 group-focus-within:rotate-180"
          />
        </span>
      </div>
    </div>
    """
  end

  defp task_priority_value(priority) when is_atom(priority), do: Atom.to_string(priority)
  defp task_priority_value(priority) when is_binary(priority), do: priority
  defp task_priority_value(_priority), do: "normal"

  defp task_approval_status_badge_class(:approved), do: "badge-success"
  defp task_approval_status_badge_class(:rejected), do: "badge-neutral"
  defp task_approval_status_badge_class(_status), do: "badge-warning"

  attr :status, :atom, required: true

  defp draft_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-semibold",
      draft_status_badge_class(@status)
    ]}>
      <.icon name={draft_status_icon(@status)} class="size-3.5" />
      {Phoenix.Naming.humanize(@status)}
    </span>
    """
  end

  defp draft_status_badge_class(:approved), do: "border-primary/25 bg-primary/10 text-primary"

  defp draft_status_badge_class(:pending),
    do: "border-secondary/25 bg-secondary/10 text-secondary"

  defp draft_status_badge_class(_status),
    do: "border-base-content/15 bg-base-200 text-base-content/60"

  defp draft_status_icon(:approved), do: "icon-[tabler--circle-check]"
  defp draft_status_icon(:pending), do: "icon-[tabler--clock]"
  defp draft_status_icon(_status), do: "icon-[tabler--circle]"

  defp task_approval_confidence(nil), do: gettext("AI confidence unavailable")

  defp task_approval_confidence(confidence) do
    gettext("AI confidence: %{score}%", score: round(confidence * 100))
  end

  defp present_or(value, fallback) when is_binary(value) do
    if String.trim(value) == "", do: fallback, else: value
  end

  defp present_or(_value, fallback), do: fallback

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.page title={gettext("Workflows")}>
        <div id="automation-screen" class="space-y-4">
          <section
            id="automation-workspace"
            class="rounded-lg border border-base-content/10 bg-base-100"
          >
            <div class="px-4 pt-3 sm:px-5">
              <.form
                for={@automation_tab_form}
                id="automation-tab-mobile-form"
                phx-change="change_automation_tab"
                class="mb-3 sm:hidden"
                aria-label={gettext("Automation tab")}
              >
                <div class="group relative w-full">
                  <span class="pointer-events-none absolute inset-y-0 left-3 z-20 flex items-center">
                    <span class="flex size-6 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
                      <.icon name={automation_tab_icon(@automation_tab)} class="size-3.5" />
                    </span>
                  </span>
                  <.live_select
                    field={@automation_tab_form[:tab]}
                    id="automation-tab-mobile-select"
                    options={automation_tab_options()}
                    value={@automation_tab}
                    placeholder={gettext("Search automation sections…")}
                    style={:none}
                    debounce={100}
                    update_min_len={0}
                    container_class="relative w-full"
                    text_input_class="input h-10 w-full cursor-pointer pl-11 pr-10 text-sm font-medium placeholder:text-base-content/40 focus:cursor-text"
                    dropdown_class="absolute left-0 top-[calc(100%+4px)] z-[300] max-h-60 w-full overflow-y-auto rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-xl shadow-base-content/10"
                    option_class="flex w-full items-center gap-2 rounded-md px-2.5 py-2 text-sm"
                    available_option_class="cursor-pointer rounded-md hover:bg-base-200/70"
                    selected_option_class="cursor-pointer rounded-md bg-base-200/70 font-semibold"
                    active_option_class="bg-base-200"
                  >
                    <:option :let={option}>
                      <span class="flex size-6 shrink-0 items-center justify-center rounded-md border border-primary/15 bg-primary/10 text-primary/70">
                        <.icon name={automation_tab_icon(option.value)} class="size-3.5" />
                      </span>
                      <span class="min-w-0 flex-1 truncate">{option.label}</span>
                      <span
                        :if={option.value == "task_suggestions" && @task_approval_total > 0}
                        class="badge badge-primary badge-sm min-h-5 min-w-5 shrink-0 rounded-full border-0 px-1.5 text-[10px] font-bold leading-none"
                      >
                        {@task_approval_total}
                      </span>
                      <span
                        :if={option.value == "email_drafts" && @draft_total > 0}
                        class="badge badge-primary badge-sm min-h-5 min-w-5 shrink-0 rounded-full border-0 px-1.5 text-[10px] font-bold leading-none"
                      >
                        {@draft_total}
                      </span>
                    </:option>
                  </.live_select>
                  <span class="pointer-events-none absolute inset-y-0 right-2 z-20 flex items-center text-base-content/45">
                    <.icon
                      name="icon-[tabler--chevron-down]"
                      class="size-4 transition-transform duration-200 group-focus-within:rotate-180"
                    />
                  </span>
                </div>
              </.form>
              <nav
                id="automation-tabs"
                class="tabs tabs-bordered hidden overflow-x-auto sm:flex"
                aria-label={gettext("Automation tabs")}
                role="tablist"
                aria-orientation="horizontal"
              >
                <.link
                  :for={tab <- automation_tabs()}
                  id={"automation-tab-#{tab.id}"}
                  class={[
                    "tab active-tab:tab-active active-tab:border-primary active-tab:text-primary gap-2 whitespace-nowrap rounded-none!",
                    @automation_tab == tab.id && "active tab-active"
                  ]}
                  data-tab={tab.id}
                  patch={~p"/automation?tab=#{tab.id}"}
                  aria-controls={"automation-panel-#{tab.id}"}
                  role="tab"
                  aria-selected={@automation_tab == tab.id}
                >
                  <.icon name={tab.icon} class="size-4.5 shrink-0" />
                  {tab.label}
                  <span
                    :if={tab.id == "task_suggestions" && @task_approval_total > 0}
                    id="automation-tab-task-suggestions-count"
                    class="badge badge-primary badge-sm min-h-5 min-w-5 rounded-full border-0 px-1.5 text-[10px] font-bold leading-none"
                    aria-label={
                      ngettext("1 task suggestion", "%{count} task suggestions", @task_approval_total)
                    }
                  >
                    {@task_approval_total}
                  </span>
                  <span
                    :if={tab.id == "email_drafts" && @draft_total > 0}
                    id="automation-tab-email-drafts-count"
                    class="badge badge-primary badge-sm min-h-5 min-w-5 rounded-full border-0 px-1.5 text-[10px] font-bold leading-none"
                    aria-label={ngettext("1 email draft", "%{count} email drafts", @draft_total)}
                  >
                    {@draft_total}
                  </span>
                </.link>
              </nav>
            </div>

            <section
              id="automation-panel-configuration"
              class={@automation_tab != "configuration" && "hidden"}
              role="tabpanel"
              aria-labelledby="automation-tab-configuration"
            >
              <div class="grid gap-4 p-4 xl:grid-cols-[minmax(18rem,23rem)_1fr]">
                <section class="rounded-lg border border-base-content/10 bg-base-100">
                  <div class="border-b border-base-content/10 p-4">
                    <h2 class="text-sm font-semibold text-base-content">
                      {gettext("Active workflows")}
                    </h2>
                    <p class="mt-1 text-xs text-base-content/55">
                      {gettext("Pick a workflow to inspect or create a new one below.")}
                    </p>
                  </div>

                  <div
                    aria-busy={@loading}
                    class="max-h-[22rem] overflow-y-auto p-2"
                  >
                    <div
                      :if={@loading}
                      id="sequences-loading"
                      class="space-y-2"
                      aria-label={gettext("Loading workflows")}
                    >
                      <div
                        id="workflow-skeleton"
                        class="rounded-md border border-base-content/10 p-3"
                      >
                        <div class="flex items-center justify-between gap-3">
                          <div class="skeleton h-4 w-32 rounded-md" />
                          <div class="skeleton h-6 w-20 rounded-md" />
                        </div>
                        <div class="mt-2 flex items-center gap-2">
                          <div class="skeleton h-3 w-24 rounded-md" />
                          <div class="skeleton size-1.5 rounded-full" />
                          <div class="skeleton h-3 w-20 rounded-md" />
                        </div>
                      </div>
                    </div>
                    <div :if={!@loading} id="sequences" phx-update="stream">
                      <div
                        id="sequences-empty"
                        class="hidden only:block rounded-md border border-dashed border-base-content/15 p-4 text-sm text-base-content/50"
                      >
                        {gettext("No workflows yet. Create your first one below.")}
                      </div>
                      <button
                        :for={{id, sequence} <- @streams.sequences}
                        id={id}
                        type="button"
                        phx-click="select_sequence"
                        phx-value-id={sequence.id}
                        class={[
                          "mb-1 w-full rounded-md border px-3 py-2 text-left transition-colors hover:border-primary/30 hover:bg-base-200/70",
                          @active_sequence && @active_sequence.id == sequence.id &&
                            "border-primary/40 bg-primary/8"
                        ]}
                      >
                        <div class="flex items-center justify-between gap-2">
                          <span class="truncate text-sm font-semibold text-base-content">
                            {sequence.name}
                          </span>
                          <.workflow_status_badge status={sequence.status} />
                        </div>
                        <div class="mt-1 flex min-w-0 items-center gap-2 text-xs text-base-content/50">
                          <span class="truncate">{trigger_label(sequence.trigger_type)}</span>
                          <span class="size-1 rounded-full bg-base-content/25"></span>
                          <span>{mode_label(sequence_mode(sequence))}</span>
                        </div>
                      </button>
                    </div>
                  </div>

                  <div :if={@can_create_workflow?} class="border-t border-base-content/10 p-4">
                    <h3 class="mb-3 text-xs font-semibold uppercase text-base-content/45">
                      {gettext("New workflow")}
                    </h3>
                    <div class="space-y-2">
                      <button
                        :for={workflow <- workflow_cards(assigns)}
                        id={"workflow-card-#{workflow.id}"}
                        type="button"
                        phx-click={choose_workflow_js(workflow.id)}
                        class={[
                          "w-full rounded-lg border p-3 text-left transition-all hover:border-primary/35 hover:bg-base-200/60",
                          workflow.active? &&
                            "border-primary/45 bg-primary/8 shadow-sm shadow-primary/10"
                        ]}
                      >
                        <div class="flex items-start gap-3">
                          <div class="flex size-9 shrink-0 items-center justify-center rounded-md bg-base-200 text-primary">
                            <.icon name={workflow.icon} class="size-5" />
                          </div>
                          <div class="min-w-0">
                            <p class="text-sm font-semibold text-base-content">{workflow.name}</p>
                            <p class="mt-0.5 text-xs text-base-content/55">{workflow.summary}</p>
                          </div>
                        </div>
                      </button>
                    </div>
                  </div>
                </section>

                <div>
                  <section id="workflow-builder">
                    <div id="workflow-builder-header" class="border-b border-base-content/10 p-4">
                      <h2 class="text-sm font-semibold text-base-content">
                        {gettext("Configure workflow")}
                      </h2>
                      <p class="mt-1 text-xs text-base-content/55">
                        {gettext(
                          "Start with one of the safe CRM workflows. You can tune timing, approval mode, and exclusions."
                        )}
                      </p>
                    </div>

                    <div class="grid gap-0">
                      <.form
                        :if={@can_create_workflow? && is_nil(@active_sequence)}
                        for={@sequence_form}
                        id="automation-sequence-form"
                        phx-submit="save_sequence"
                        class="p-4"
                      >
                        <input
                          type="hidden"
                          name={@sequence_form[:workflow_type].name}
                          value={@selected_workflow}
                        />
                        <div class="space-y-4">
                          <.input field={@sequence_form[:name]} type="text" label={gettext("Name")} />
                          <.action_mode_select
                            :if={@selected_workflow != "inbound_email_reply"}
                            field={@sequence_form[:mode]}
                            workflow={@selected_workflow}
                          />
                          <div
                            :if={@selected_workflow == "inbound_email_reply"}
                            id="ai-reply-review-mode"
                            class="rounded-lg border border-primary/20 bg-primary/5 px-3 py-2.5 text-sm text-base-content/70"
                          >
                            <span class="font-semibold text-base-content">
                              {gettext("Action mode:")}
                            </span>
                            {" "}{gettext("Review AI reply")}
                          </div>
                          <.input
                            :if={@selected_workflow == "no_reply_follow_up"}
                            field={@sequence_form[:idle_days]}
                            type="number"
                            label={gettext("Follow up after days")}
                            min="1"
                          />
                          <.input
                            :if={@selected_workflow == "no_reply_follow_up"}
                            field={@sequence_form[:subject]}
                            type="text"
                            label={gettext("Email subject")}
                          />
                          <.input
                            field={@sequence_form[:excluded_senders]}
                            type="textarea"
                            label={gettext("Ignore sender patterns")}
                            class="w-full textarea min-h-28 font-mono text-xs"
                          />
                          <button
                            id="save-sequence-button"
                            type="submit"
                            class="btn btn-primary w-full gap-2"
                          >
                            <.icon name="icon-[tabler--plus]" class="size-4" />
                            {gettext("Create workflow")}
                          </button>
                        </div>
                      </.form>

                      <div :if={@active_sequence} id="sequence-builder" class="space-y-5 p-4">
                        <div class="flex flex-wrap items-start justify-between gap-3">
                          <div>
                            <div class="mb-2 flex flex-wrap items-center gap-2">
                              <.workflow_status_badge status={@active_sequence.status} />
                              <span class="badge badge-sm badge-ghost rounded-md px-2.5">
                                {mode_label(sequence_mode(@active_sequence))}
                              </span>
                            </div>
                            <h2 class="text-lg font-semibold text-base-content">
                              {@active_sequence.name}
                            </h2>
                            <p class="mt-1 text-sm text-base-content/55">
                              {workflow_display_description(@active_sequence)}
                            </p>
                          </div>
                          <div class="flex flex-wrap gap-2">
                            <button
                              :if={@can_update_workflow? && @active_sequence.status != :active}
                              id="activate-sequence-button"
                              type="button"
                              phx-click="activate_sequence"
                              phx-value-id={@active_sequence.id}
                              class="btn btn-primary btn-sm gap-2"
                            >
                              <.icon name="icon-[tabler--player-play]" class="size-4" />
                              {gettext("Activate")}
                            </button>
                            <button
                              :if={@can_update_workflow? && @active_sequence.status == :active}
                              id="pause-sequence-button"
                              type="button"
                              phx-click="pause_sequence"
                              phx-value-id={@active_sequence.id}
                              class="btn btn-warning btn-sm gap-2"
                            >
                              <.icon name="icon-[tabler--player-pause]" class="size-4" />
                              {gettext("Pause")}
                            </button>
                            <button
                              :if={@can_update_workflow?}
                              id="archive-sequence-button"
                              type="button"
                              phx-click="archive_sequence"
                              phx-value-id={@active_sequence.id}
                              class="btn btn-ghost btn-sm gap-2"
                            >
                              <.icon name="icon-[tabler--archive]" class="size-4" />
                              {gettext("Archive")}
                            </button>
                          </div>
                        </div>

                        <div class="grid gap-3 md:grid-cols-3">
                          <div class="rounded-lg border border-base-content/10 bg-base-200/35 p-3">
                            <p class="text-xs font-semibold uppercase text-base-content/40">
                              {gettext("Trigger")}
                            </p>
                            <p class="mt-1 text-sm font-medium text-base-content">
                              {trigger_label(@active_sequence.trigger_type)}
                            </p>
                          </div>
                          <div class="rounded-lg border border-base-content/10 bg-base-200/35 p-3">
                            <p class="text-xs font-semibold uppercase text-base-content/40">
                              {gettext("Safety")}
                            </p>
                            <p class="mt-1 text-sm font-medium text-base-content">
                              {gettext("Suppression list")}
                            </p>
                          </div>
                          <div class="rounded-lg border border-base-content/10 bg-base-200/35 p-3">
                            <p class="text-xs font-semibold uppercase text-base-content/40">
                              {gettext("Ignored")}
                            </p>
                            <details class="group relative mt-1">
                              <summary
                                class="flex w-full cursor-pointer list-none items-center gap-1.5 rounded-md text-left text-sm font-medium text-base-content outline-none transition-colors hover:bg-base-content/5 focus-visible:ring-2 focus-visible:ring-primary/40"
                                title={sequence_excluded_senders(@active_sequence)}
                              >
                                <span class="min-w-0 flex-1 truncate">
                                  {excluded_senders_preview(@active_sequence)}
                                </span>
                                <.icon
                                  name="icon-[tabler--chevron-down]"
                                  class="size-4 shrink-0 text-base-content/45 transition-transform duration-200 group-open:rotate-180"
                                />
                              </summary>
                              <div class="absolute left-0 top-full z-30 mt-2 w-72 max-w-[calc(100vw-3rem)] rounded-lg border border-base-content/15 bg-base-100 p-2 shadow-lg shadow-base-content/10">
                                <p class="px-2 py-1 text-xs font-semibold uppercase tracking-wide text-base-content/45">
                                  {gettext("Ignored sender patterns")}
                                </p>
                                <ul class="max-h-48 space-y-1 overflow-y-auto p-1">
                                  <li
                                    :for={
                                      sender <- sequence_excluded_sender_patterns(@active_sequence)
                                    }
                                    class="break-all rounded-md bg-base-200/55 px-2 py-1.5 font-mono text-xs text-base-content/75"
                                  >
                                    {sender}
                                  </li>
                                  <li
                                    :if={sequence_excluded_sender_patterns(@active_sequence) == []}
                                    class="px-2 py-1.5 text-xs text-base-content/50"
                                  >
                                    {gettext("No sender patterns are ignored.")}
                                  </li>
                                </ul>
                              </div>
                            </details>
                          </div>
                        </div>

                        <section class="max-w-3xl rounded-xl border border-base-content/15 bg-base-100 p-4 shadow-sm">
                          <h3 class="mb-3 text-sm font-semibold text-base-content">
                            {gettext("Workflow steps")}
                          </h3>
                          <div id="rules" phx-update="stream" class="space-y-2">
                            <div
                              id="rules-empty"
                              class="hidden only:block rounded-md border border-dashed border-base-content/15 p-4 text-sm text-base-content/50"
                            >
                              {gettext("This workflow has no steps yet.")}
                            </div>
                            <div
                              :for={{id, rule} <- @streams.rules}
                              id={id}
                              class="flex items-center gap-3 rounded-lg border border-base-content/15 bg-base-200/35 p-3"
                            >
                              <div class="flex size-9 shrink-0 items-center justify-center rounded-md bg-base-100 text-primary ring-1 ring-base-content/10">
                                <.icon name={rule_icon(rule.action_type)} class="size-5" />
                              </div>
                              <div class="min-w-0 flex-1">
                                <div class="flex flex-wrap items-center gap-2">
                                  <span class="text-sm font-semibold text-base-content">
                                    {rule_label(rule.action_type)}
                                  </span>
                                  <.rule_delay seconds={display_rule_delay(rule)} />
                                </div>
                                <p class="mt-1 break-words text-xs leading-relaxed text-base-content/50">
                                  {rule_summary(rule)}
                                </p>
                              </div>
                            </div>
                          </div>
                        </section>
                      </div>
                    </div>
                  </section>
                </div>
              </div>
            </section>

            <section
              id="automation-panel-task-suggestions"
              class={@automation_tab != "task_suggestions" && "hidden"}
              role="tabpanel"
              aria-labelledby="automation-tab-task_suggestions"
            >
              <div class="flex items-center justify-between border-b border-base-content/10 p-4">
                <div>
                  <h2 class="text-sm font-semibold text-base-content">
                    {gettext("Task suggestions")}
                  </h2>
                  <p class="mt-1 text-xs text-base-content/55">
                    {gettext("Review suggestions before creating real tasks in Tasks.")}
                  </p>
                </div>
                <%= if @loading do %>
                  <span
                    class="skeleton h-6 w-8 rounded-md"
                    aria-label={gettext("Loading approvals")}
                  />
                <% else %>
                  <div class="flex items-center gap-2">
                    <span class="badge badge-primary">{@task_approval_total}</span>
                    <button
                      :if={@task_approval_total > 0}
                      id="clear-all-task-approvals"
                      type="button"
                      phx-click="clear_all_task_approvals"
                      phx-disable-with={gettext("Clearing...")}
                      data-confirm={gettext("Clear all task suggestions? This cannot be undone.")}
                      class="btn btn-error btn-xs h-7 min-h-7 gap-1.5 shadow-sm"
                    >
                      <.icon name="icon-[tabler--trash]" class="size-3.5" />
                      {gettext("Clear all")}
                    </button>
                  </div>
                <% end %>
              </div>

              <div class="p-4">
                <div :if={@loading} id="task-approvals-loading" class="space-y-3">
                  <div
                    :for={_ <- 1..2}
                    class="rounded-lg border border-base-content/10 bg-base-200/35 p-4"
                  >
                    <div class="flex items-start justify-between gap-4">
                      <div class="min-w-0 flex-1 space-y-2">
                        <div class="skeleton h-4 w-20 rounded-md" />
                        <div class="skeleton h-4 w-3/5 rounded-md" />
                        <div class="skeleton h-3 w-2/5 rounded-md" />
                      </div>
                      <div class="skeleton h-7 w-20 rounded-md" />
                    </div>
                    <div class="mt-5 grid gap-3 sm:grid-cols-2">
                      <div class="skeleton h-10 rounded-md" />
                      <div class="skeleton h-10 rounded-md" />
                    </div>
                  </div>
                </div>

                <div id="task-approvals" phx-update="stream" class="space-y-3">
                  <div
                    :if={!@loading}
                    id="task-approvals-empty"
                    class="hidden only:block rounded-md border border-dashed border-base-content/15 p-4 text-center text-sm text-base-content/50"
                  >
                    {gettext("No task suggestions need approval.")}
                  </div>
                  <div
                    :for={{id, approval} <- @streams.task_approvals}
                    id={id}
                    class="rounded-lg border border-base-content/10 bg-base-200/35 p-4"
                  >
                    <div class="mb-3 flex flex-wrap items-start justify-between gap-3">
                      <div class="min-w-0">
                        <div class="mb-1 flex flex-wrap items-center gap-2">
                          <span class="badge badge-sm badge-ghost gap-1">
                            <.icon name="icon-[tabler--checkbox]" class="size-3.5" />
                            {gettext("Task")}
                          </span>
                          <span class={[
                            "badge badge-sm",
                            task_approval_status_badge_class(approval.status)
                          ]}>
                            {Phoenix.Naming.humanize(approval.status)}
                          </span>
                        </div>
                        <h3 class="truncate text-sm font-semibold text-base-content">
                          {approval.title}
                        </h3>
                        <div class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1">
                          <p class="truncate text-xs text-base-content/50">
                            {task_approval_contact_label(approval)} | {task_approval_source_label(
                              approval
                            )}
                          </p>
                          <.source_thread_link
                            :if={approval.email_thread_id}
                            id={"task-approval-source-thread-#{approval.id}"}
                            thread_id={approval.email_thread_id}
                          />
                        </div>
                        <p class="mt-1 text-xs text-base-content/45">
                          {task_approval_confidence(approval.confidence)}
                        </p>
                      </div>
                    </div>

                    <%= if approval.status == :pending do %>
                      <% task_form = task_approval_form(approval) %>
                      <.form
                        for={task_form}
                        id={"task-approval-form-#{approval.id}"}
                        phx-submit="approve_task_approval"
                        class="space-y-3"
                      >
                        <input type="hidden" name="_id" value={approval.id} />
                        <.input
                          id={"task-approval-title-#{approval.id}"}
                          field={task_form[:title]}
                          type="text"
                          label={gettext("Title")}
                        />
                        <.input
                          id={"task-approval-description-#{approval.id}"}
                          field={task_form[:description]}
                          type="textarea"
                          label={gettext("Description")}
                          class="w-full textarea min-h-24"
                        />
                        <div class="grid gap-3 sm:grid-cols-2">
                          <.input
                            id={"task-approval-due-date-#{approval.id}"}
                            field={task_form[:due_date]}
                            type="datetime-local"
                            label={gettext("Due date")}
                          />
                          <.task_approval_priority_select
                            id={"task-approval-priority-#{approval.id}"}
                            field={task_form[:priority]}
                          />
                        </div>
                        <div class="flex justify-end gap-2">
                          <button
                            type="button"
                            phx-click="reject_task_approval"
                            phx-value-id={approval.id}
                            class="btn btn-ghost btn-sm gap-2"
                          >
                            <.icon name="icon-[tabler--x]" class="size-4" />
                            {gettext("Reject")}
                          </button>
                          <button type="submit" class="btn btn-primary btn-sm gap-2">
                            <.icon name="icon-[tabler--check]" class="size-4" />
                            {gettext("Create task")}
                          </button>
                        </div>
                      </.form>
                    <% end %>
                  </div>
                </div>
                <.approval_pagination
                  id="task-approvals-pagination"
                  page={@task_approval_page}
                  page_count={@task_approval_page_count}
                  event="change_task_approval_page"
                />
              </div>
            </section>

            <section
              id="automation-panel-email-drafts"
              class={@automation_tab != "email_drafts" && "hidden"}
              role="tabpanel"
              aria-labelledby="automation-tab-email_drafts"
            >
              <div class="flex items-center justify-between border-b border-base-content/10 p-4">
                <div>
                  <h2 class="text-sm font-semibold text-base-content">{gettext("Email drafts")}</h2>
                  <p class="mt-1 text-xs text-base-content/55">
                    {gettext("Review drafts before approving them to send.")}
                  </p>
                </div>
                <%= if @loading do %>
                  <span class="skeleton h-6 w-8 rounded-md" aria-label={gettext("Loading drafts")} />
                <% else %>
                  <div class="flex items-center gap-2">
                    <span class="badge badge-primary">{@draft_total}</span>
                    <button
                      :if={@draft_total > 0}
                      id="clear-all-drafts"
                      type="button"
                      phx-click="clear_all_drafts"
                      phx-disable-with={gettext("Clearing...")}
                      data-confirm={gettext("Clear all email drafts? This cannot be undone.")}
                      class="btn btn-error btn-xs h-7 min-h-7 gap-1.5 shadow-sm"
                    >
                      <.icon name="icon-[tabler--trash]" class="size-3.5" />
                      {gettext("Clear all")}
                    </button>
                  </div>
                <% end %>
              </div>

              <div class="p-4">
                <div :if={@loading} id="drafts-loading" class="space-y-3">
                  <div
                    :for={_ <- 1..2}
                    class="rounded-lg border border-base-content/10 bg-base-200/35 p-4"
                  >
                    <div class="flex items-start justify-between gap-4">
                      <div class="min-w-0 flex-1 space-y-2">
                        <div class="skeleton h-4 w-1/2 rounded-md" />
                        <div class="skeleton h-3 w-1/3 rounded-md" />
                      </div>
                      <div class="skeleton h-6 w-20 rounded-md" />
                    </div>
                    <div class="mt-5 space-y-2">
                      <div class="skeleton h-3 w-full rounded-md" />
                      <div class="skeleton h-3 w-4/5 rounded-md" />
                    </div>
                  </div>
                </div>

                <div id="drafts" phx-update="stream" class="space-y-3">
                  <div
                    :if={!@loading}
                    id="drafts-empty"
                    class="hidden only:block rounded-md border border-dashed border-base-content/15 p-4 text-center text-sm text-base-content/50"
                  >
                    {gettext("No drafts need approval.")}
                  </div>
                  <div
                    :for={{id, draft} <- @streams.drafts}
                    id={id}
                    class={[
                      "rounded-lg border border-base-content/10 bg-base-200/35 p-4 transition-[opacity,transform,max-height,padding,margin,border-color] duration-200 ease-in",
                      draft_transition_action(@draft_transition, draft.id) == :reject &&
                        "max-h-0 translate-x-2 overflow-hidden border-transparent p-0 opacity-0"
                    ]}
                  >
                    <div class="mb-3 flex flex-wrap items-start justify-between gap-3">
                      <div>
                        <h3 class="text-sm font-semibold text-base-content">
                          {draft.subject || gettext("(no subject)")}
                        </h3>
                        <div class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1">
                          <p class="text-xs text-base-content/50">{draft_contact_label(draft)}</p>
                          <.source_thread_link
                            :if={draft.email_thread_id}
                            id={"draft-source-thread-#{draft.id}"}
                            thread_id={draft.email_thread_id}
                          />
                        </div>
                      </div>
                      <.draft_status_badge status={draft.status} />
                    </div>

                    <%= if draft.status == :pending do %>
                      <% draft_form = to_form(%{"body" => draft.body}, as: :draft) %>
                      <.form
                        for={draft_form}
                        id={"draft-approval-form-#{draft.id}"}
                        phx-submit="approve_draft"
                        class={[
                          "max-h-[32rem] space-y-3 overflow-hidden transition-[opacity,transform,max-height,margin] duration-200 ease-in",
                          draft_transition_action(@draft_transition, draft.id) == :approve &&
                            "max-h-0 -translate-y-1 opacity-0"
                        ]}
                      >
                        <input type="hidden" name="_id" value={draft.id} />
                        <.input
                          id={"draft-approval-body-#{draft.id}"}
                          field={draft_form[:body]}
                          type="textarea"
                          label={gettext("Body")}
                          class="w-full textarea min-h-28"
                        />
                        <div class="flex justify-end gap-2">
                          <button
                            type="button"
                            phx-click="reject_draft"
                            phx-value-id={draft.id}
                            disabled={
                              not is_nil(draft_transition_action(@draft_transition, draft.id))
                            }
                            class="btn btn-ghost btn-sm gap-2"
                          >
                            <.icon name="icon-[tabler--x]" class="size-4" />
                            {gettext("Reject")}
                          </button>
                          <button
                            type="submit"
                            disabled={
                              not is_nil(draft_transition_action(@draft_transition, draft.id))
                            }
                            class="btn btn-primary btn-sm gap-2"
                          >
                            <.icon name="icon-[tabler--check]" class="size-4" />
                            {gettext("Approve")}
                          </button>
                        </div>
                      </.form>
                    <% end %>

                    <div
                      :if={draft.status == :approved}
                      class="flex items-center justify-between gap-3"
                    >
                      <p class="line-clamp-2 text-sm text-base-content/65">{draft.body}</p>
                      <div class="flex shrink-0 items-center gap-2">
                        <%= if is_nil(draft.contact_id) do %>
                          <button
                            id={"create-draft-contact-#{draft.id}"}
                            type="button"
                            phx-click="create_draft_contact"
                            phx-value-id={draft.id}
                            class="btn btn-primary btn-sm gap-2"
                          >
                            <.icon name="icon-[tabler--user-plus]" class="size-4" />
                            {gettext("Create contact & return to review")}
                          </button>
                        <% else %>
                          <button
                            id={"unapprove-draft-#{draft.id}"}
                            type="button"
                            phx-click="unapprove_draft"
                            phx-value-id={draft.id}
                            class="btn btn-ghost btn-sm gap-2"
                          >
                            <.icon name="icon-[tabler--arrow-back-up]" class="size-4" />
                            {gettext("Return to review")}
                          </button>
                          <button
                            id={"send-draft-#{draft.id}"}
                            type="button"
                            phx-click="send_draft"
                            phx-value-id={draft.id}
                            class="btn btn-primary btn-sm gap-2"
                          >
                            <.icon name="icon-[tabler--send]" class="size-4" />
                            {gettext("Send")}
                          </button>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>
                <.approval_pagination
                  id="drafts-pagination"
                  page={@draft_page}
                  page_count={@draft_page_count}
                  event="change_draft_page"
                />
              </div>
            </section>
          </section>
        </div>
      </Layouts.page>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :page, :integer, required: true
  attr :page_count, :integer, required: true
  attr :event, :string, required: true

  defp approval_pagination(assigns) do
    ~H"""
    <nav
      :if={@page_count > 1}
      id={@id}
      class="mt-4 flex items-center justify-between gap-3 border-t border-base-content/10 pt-3"
      aria-label={gettext("Approval pagination")}
    >
      <span class="text-xs text-base-content/55">
        {gettext("Page %{page} of %{total}", page: @page, total: @page_count)}
      </span>
      <div class="join">
        <button
          id={"#{@id}-previous"}
          type="button"
          phx-click={@event}
          phx-value-page={@page - 1}
          disabled={@page == 1}
          class="btn btn-sm join-item"
        >
          <.icon name="icon-[tabler--chevron-left]" class="size-4" />
          {gettext("Previous")}
        </button>
        <button
          id={"#{@id}-next"}
          type="button"
          phx-click={@event}
          phx-value-page={@page + 1}
          disabled={@page == @page_count}
          class="btn btn-sm join-item"
        >
          {gettext("Next")}
          <.icon name="icon-[tabler--chevron-right]" class="size-4" />
        </button>
      </div>
    </nav>
    """
  end
end
