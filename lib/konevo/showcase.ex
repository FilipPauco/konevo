defmodule Konevo.Showcase do
  @moduledoc """
  Seeds an explicitly selected workspace with fictional data for product screenshots.

  Set `KONEVO_SHOWCASE_DATA=true` before calling the functions in this module.
  """

  import Ecto.Query

  alias Konevo.Accounts.{Membership, Organization, User}
  alias Konevo.Automation.{Rule, Sequence, TaskApproval}
  alias Konevo.Companies.Company
  alias Konevo.Contacts.Contact
  alias Konevo.Deals.{Deal, DealStage, DefaultStages}
  alias Konevo.Inbox.{Email, EmailThread}
  alias Konevo.Messaging.MessageDraft
  alias Konevo.Repo
  alias Konevo.Tasks.Task

  @marker "konevo-showcase-data"
  @thread_prefix "konevo-showcase-"

  @doc """
  Replaces only Konevo showcase records in the selected organization.
  """
  def seed do
    ensure_enabled!()

    Repo.transaction(fn ->
      {organization, user} = target!()
      clear_records(organization.id)
      {:ok, _} = DefaultStages.ensure(organization)

      companies = insert_companies(organization, user)
      contacts = insert_contacts(organization, user, companies)
      deals = insert_deals(organization, user, contacts)
      threads = insert_threads(organization, user, contacts, deals)
      insert_tasks(organization, user, contacts, deals)
      workflows = insert_workflows(organization, user, contacts, threads)

      %{
        companies: map_size(companies),
        contacts: map_size(contacts),
        deals: map_size(deals),
        workflows: map_size(workflows),
        task_approvals: 2,
        email_drafts: 2
      }
    end)
  end

  @doc """
  Deletes only the fictional Konevo showcase records in the selected organization.
  """
  def clear do
    ensure_enabled!()

    Repo.transaction(fn ->
      {organization, _user} = target!()
      clear_records(organization.id)
      :ok
    end)
  end

  defp ensure_enabled! do
    if System.get_env("KONEVO_SHOWCASE_DATA") != "true" do
      raise "Set KONEVO_SHOWCASE_DATA=true before seeding or clearing showcase data."
    end
  end

  defp target! do
    slug = System.get_env("KONEVO_SHOWCASE_ORG_SLUG") || "public"
    organization = Repo.get_by!(Organization, slug: slug)

    user =
      from(m in Membership,
        join: u in User,
        on: u.id == m.user_id,
        where: m.organization_id == ^organization.id and is_nil(m.archived_at),
        order_by: [asc: m.id],
        limit: 1,
        select: u
      )
      |> Repo.one!()

    {organization, user}
  end

  defp clear_records(organization_id) do
    thread_ids =
      from(t in EmailThread,
        where:
          t.organization_id == ^organization_id and
            like(t.thread_id_gmail, ^"#{@thread_prefix}%"),
        select: t.id
      )
      |> Repo.all()

    email_ids =
      from(e in Email, where: e.thread_id in ^thread_ids, select: e.id)
      |> Repo.all()

    sequence_ids = showcase_sequence_ids(organization_id)

    Repo.delete_all(from(approval in TaskApproval, where: approval.email_id in ^email_ids))
    Repo.delete_all(from(draft in MessageDraft, where: draft.source_email_id in ^email_ids))
    Repo.delete_all(from(rule in Rule, where: rule.sequence_id in ^sequence_ids))
    Repo.delete_all(from(sequence in Sequence, where: sequence.id in ^sequence_ids))
    Repo.delete_all(from(e in Email, where: e.thread_id in ^thread_ids))
    Repo.delete_all(from(t in EmailThread, where: t.id in ^thread_ids))
    Repo.delete_all(showcase_records(Task, organization_id))
    Repo.delete_all(showcase_records(Deal, organization_id))
    Repo.delete_all(showcase_records(Contact, organization_id))
    Repo.delete_all(showcase_records(Company, organization_id))
  end

  defp showcase_sequence_ids(organization_id) do
    from(sequence in Sequence,
      where:
        sequence.organization_id == ^organization_id and
          fragment("?->>'showcase' = 'true'", sequence.trigger_config),
      select: sequence.id
    )
    |> Repo.all()
  end

  defp showcase_records(schema, organization_id) do
    from(record in schema,
      where: record.organization_id == ^organization_id and record.archive_reason == ^@marker
    )
  end

  defp insert_companies(organization, user) do
    [
      {:northstar, "Northstar Labs", "Software", "https://northstar.example", "+421 2 555 0101"},
      {:atlas, "Atlas & Co.", "Professional services", "https://atlas.example",
       "+421 2 555 0102"},
      {:verve, "Verve Studio", "Creative agency", "https://verve.example", "+421 2 555 0103"},
      {:harbor, "Harbor Supply", "Wholesale", "https://harbor.example", "+421 2 555 0104"},
      {:luma, "Luma Health", "Healthcare", "https://luma.example", "+421 2 555 0105"}
    ]
    |> Map.new(fn {key, name, industry, website, phone} ->
      company =
        Repo.insert!(%Company{
          name: name,
          slug: "showcase-#{key}",
          industry: industry,
          website: website,
          phone: phone,
          linkedin_url: "https://www.linkedin.com/company/#{key}",
          notes: "Fictional company for Konevo product screenshots.",
          archive_reason: @marker,
          organization_id: organization.id,
          user_id: user.id
        })

      {key, company}
    end)
  end

  defp insert_contacts(organization, user, companies) do
    [
      {:ava, "Ava", "Simmons", "ava@northstarlabs.test", :prospect, :northstar},
      {:marcus, "Marcus", "Chen", "marcus@atlasandco.test", :lead, :atlas},
      {:nina, "Nina", "Horvath", "nina@vervestudio.test", :customer, :verve},
      {:oliver, "Oliver", "Reed", "oliver@harborsupply.test", :prospect, :harbor},
      {:sofia, "Sofia", "Novak", "sofia@lumahealth.test", :lead, :luma}
    ]
    |> Map.new(fn {key, first_name, last_name, email, status, company_key} ->
      contact =
        Repo.insert!(%Contact{
          first_name: first_name,
          last_name: last_name,
          slug: "showcase-#{key}",
          email: email,
          phone:
            "+421 903 555 #{String.pad_leading(to_string(map_size(companies) + 10), 3, "0")}",
          linkedin_url: "https://www.linkedin.com/in/#{key}-showcase",
          status: status,
          notes: "Fictional contact for Konevo product screenshots.",
          archive_reason: @marker,
          organization_id: organization.id,
          user_id: user.id,
          company_id: Map.fetch!(companies, company_key).id
        })

      {key, contact}
    end)
  end

  defp insert_deals(organization, user, contacts) do
    stages =
      from(s in DealStage, where: s.organization_id == ^organization.id, select: {s.name, s})
      |> Repo.all()
      |> Map.new()

    now = DateTime.utc_now(:second)
    today = Date.utc_today()

    [
      {:northstar, "Northstar annual workspace", "Qualified", :ava, "8400.00", 65, 4, 2},
      {:atlas, "Atlas onboarding", "Lead", :marcus, "3200.00", 30, 12, 5},
      {:verve, "Verve Studio expansion", "Proposal", :nina, "6750.00", 70, 8, 3},
      {:harbor, "Harbor supply rollout", "Negotiation", :oliver, "12000.00", 85, 18, 6},
      {:luma, "Luma Health pilot", "Closed Won", :sofia, "4900.00", 100, 1, 1}
    ]
    |> Map.new(fn {key, title, stage_name, contact_key, value, probability, close_in, action_in} ->
      deal =
        Repo.insert!(%Deal{
          title: title,
          slug: "showcase-#{key}",
          description: "A fictional pipeline opportunity for product screenshots.",
          value: Decimal.new(value),
          currency: "EUR",
          probability: probability,
          expected_close_date: Date.add(today, close_in),
          next_action: "Confirm next steps",
          next_action_due_date: DateTime.add(now, action_in * 86_400, :second),
          source: "email",
          archive_reason: @marker,
          organization_id: organization.id,
          contact_id: Map.fetch!(contacts, contact_key).id,
          stage_id: Map.fetch!(stages, stage_name).id,
          owner_id: user.id,
          created_by_id: user.id
        })

      {key, deal}
    end)
  end

  defp insert_threads(organization, user, contacts, deals) do
    now = DateTime.utc_now(:second)

    [
      {:northstar, "Pricing and rollout timeline", :lead, :ava, :northstar,
       "Could you share pricing for 25 seats and a rollout timeline?", 0},
      {:atlas, "A quick question about onboarding", :lead, :marcus, :atlas,
       "We would like to see how the shared inbox works for a small team.", 0},
      {:verve, "Proposal feedback", :customer, :nina, :verve,
       "The proposal looks good. Can we align on the implementation milestones?", 0},
      {:harbor, "Next steps for the supply rollout", :lead, :oliver, :harbor,
       "Please send the updated scope before our Friday review.", 0},
      {:luma, "Welcome to Konevo", :customer, :sofia, :luma,
       "Thanks for the smooth pilot launch. The team is already using the inbox daily.", 0},
      {:northstar_demo, "Demo availability this week", :lead, :ava, :northstar,
       "Could we reserve a 30-minute demo slot on Thursday morning?", 0},
      {:atlas_permissions, "Question about team permissions", :lead, :marcus, :atlas,
       "Can workspace managers assign follow-up tasks to the sales team?", 0},
      {:verve_timeline, "Implementation timeline", :customer, :nina, :verve,
       "Our team would like to confirm the timeline before the next planning meeting.", 0},
      {:harbor_contract, "Contract review update", :lead, :oliver, :harbor,
       "Legal has one final question about the proposed rollout scope.", 0},
      {:luma_reporting, "Monthly reporting request", :customer, :sofia, :luma,
       "Could you show us the best way to review activity across our account?", 0},
      {:northstar_follow_up, "A few pricing follow-up questions", :lead, :ava, :northstar,
       "Thank you for the estimate. We have a few questions before sharing it internally.", 0},
      {:atlas_import, "Contact import format", :lead, :marcus, :atlas,
       "Which fields should we include when importing our first contact list?", 0},
      {:verve_workspace, "Adding another workspace", :customer, :nina, :verve,
       "Can we add the operations team without changing our current pipeline?", 0},
      {:harbor_meeting, "Friday meeting agenda", :lead, :oliver, :harbor,
       "Please send a short agenda so we can prepare the rollout discussion.", 0},
      {:luma_feedback, "Pilot feedback from the team", :customer, :sofia, :luma,
       "The team likes the shared inbox. We have two small improvement ideas to share.", 0}
    ]
    |> Enum.with_index()
    |> Map.new(fn {{key, subject, category, contact_key, deal_key, snippet, hours_ago}, position} ->
      contact = Map.fetch!(contacts, contact_key)
      received_at = DateTime.add(now, -(hours_ago * 3600 + position * 60), :second)

      thread =
        Repo.insert!(%EmailThread{
          organization_id: organization.id,
          thread_id_gmail: "#{@thread_prefix}#{key}",
          subject: subject,
          category: category,
          snippet: snippet,
          is_unresolved: key != :luma,
          is_favorite: key in [:northstar, :verve],
          last_activity_at: received_at,
          last_inbound_at: received_at,
          revenue_at_risk: Map.fetch!(deals, deal_key).value,
          participants: [contact.email, user.email],
          contact_id: contact.id,
          deal_id: Map.fetch!(deals, deal_key).id
        })

      email =
        Repo.insert!(%Email{
          organization_id: organization.id,
          thread_id: thread.id,
          message_id: "#{@thread_prefix}#{key}@konevo.invalid",
          from: contact.email,
          to: [user.email],
          subject: subject,
          body: snippet,
          received_at: received_at,
          is_inbound: true
        })

      {key, %{thread: thread, email: email}}
    end)
  end

  defp insert_tasks(organization, user, contacts, deals) do
    now = DateTime.utc_now(:second)

    [
      {"Review Northstar pricing request", :ava, :northstar, :urgent, -1},
      {"Prepare Atlas workspace demo", :marcus, :atlas, :high, 1},
      {"Send Verve implementation plan", :nina, :verve, :high, 3},
      {"Confirm Harbor rollout milestones", :oliver, :harbor, :normal, 5},
      {"Schedule Luma success check-in", :sofia, :luma, :normal, 7},
      {"Review weekly pipeline", :ava, :northstar, :normal, 2}
    ]
    |> Enum.with_index()
    |> Enum.each(fn {{title, contact_key, deal_key, priority, due_in}, position} ->
      Repo.insert!(%Task{
        organization_id: organization.id,
        title: title,
        description: "Fictional task for Konevo product screenshots.",
        due_date: DateTime.add(now, due_in * 86_400, :second),
        status: if(due_in == -1, do: :in_progress, else: :open),
        priority: priority,
        position: position,
        archive_reason: @marker,
        contact_id: Map.fetch!(contacts, contact_key).id,
        deal_id: Map.fetch!(deals, deal_key).id,
        assigned_to_id: user.id,
        created_by_id: user.id
      })
    end)
  end

  defp insert_workflows(organization, user, contacts, threads) do
    now = DateTime.utc_now(:second)

    [
      {:follow_up, "No-reply follow-up", :inbound_email_idle,
       "After 3 days without a customer reply, prepare a follow-up.",
       %{
         "workflow_type" => "no_reply_follow_up",
         "mode" => "manual",
         "idle_days" => 3,
         "stop_on_inbound_reply" => true,
         "approval_required" => true,
         "showcase" => true
       },
       [
         {:wait, 0, 259_200, %{}},
         {:prepare_follow_up, 1, 0,
          %{"subject" => "Following up", "mode" => "manual", "approval_required" => true}}
       ]},
      {:task, "Create tasks from lead emails", :inbound_email_received,
       "When a lead email arrives, AI prepares a task for review or automatic creation.",
       %{
         "workflow_type" => "inbound_email_task",
         "mode" => "manual",
         "idle_days" => 1,
         "approval_required" => true,
         "showcase" => true
       }, [{:prepare_task, 0, 0, %{"mode" => "manual", "ai_generated" => true}}]},
      {:reply, "AI reply to incoming emails", :inbound_email_received,
       "When an email arrives, AI writes a reply based on the email thread.",
       %{
         "workflow_type" => "inbound_email_reply",
         "mode" => "manual",
         "idle_days" => 1,
         "approval_required" => true,
         "showcase" => true
       }, [{:prepare_reply, 0, 0, %{"mode" => "manual", "ai_generated" => true}}]}
    ]
    |> Map.new(fn {key, name, trigger_type, description, trigger_config, rules} ->
      sequence =
        Repo.insert!(%Sequence{
          organization_id: organization.id,
          created_by_id: user.id,
          name: name,
          description: description,
          status: :paused,
          trigger_type: trigger_type,
          trigger_config: trigger_config
        })

      insert_workflow_rules(organization.id, sequence.id, rules)
      {key, sequence}
    end)
    |> then(fn workflows ->
      insert_task_approvals(organization, contacts, threads, workflows, now)
      insert_email_drafts(organization, user, contacts, threads)
      workflows
    end)
  end

  defp insert_workflow_rules(organization_id, sequence_id, rules) do
    Enum.each(rules, fn {action_type, position, delay_seconds, action_config} ->
      Repo.insert!(%Rule{
        organization_id: organization_id,
        sequence_id: sequence_id,
        action_type: action_type,
        position: position,
        delay_seconds: delay_seconds,
        action_config: action_config
      })
    end)
  end

  defp insert_task_approvals(organization, contacts, threads, workflows, now) do
    [
      {:northstar, :ava, "Prepare Northstar rollout plan",
       "Summarise the pricing request and propose rollout milestones.", :high, 1, 0.94},
      {:harbor, :oliver, "Confirm Harbor supply rollout milestones",
       "Extract the Friday review milestones and assign the next owner.", :urgent, 2, 0.91}
    ]
    |> Enum.each(fn {thread_key, contact_key, title, description, priority, due_in, confidence} ->
      %{thread: thread, email: email} = Map.fetch!(threads, thread_key)
      contact = Map.fetch!(contacts, contact_key)

      Repo.insert!(%TaskApproval{
        organization_id: organization.id,
        sequence_id: workflows.task.id,
        email_id: email.id,
        email_thread_id: thread.id,
        contact_id: contact.id,
        company_id: contact.company_id,
        title: title,
        description: description,
        due_date: DateTime.add(now, due_in * 86_400, :second),
        priority: priority,
        confidence: confidence,
        status: :pending
      })
    end)
  end

  defp insert_email_drafts(organization, user, contacts, threads) do
    [
      {:verve, :nina, "Re: Proposal feedback",
       "Hi Nina,\n\nThank you for the positive feedback. I will send a clear implementation plan with milestones before our next review.\n\nBest regards",
       0.93},
      {:northstar, :ava, "Following up on your rollout timeline",
       "Hi Ava,\n\nI wanted to follow up on your request for pricing and a rollout timeline. Would a short planning call this week be helpful?\n\nBest regards",
       0.9}
    ]
    |> Enum.each(fn {thread_key, contact_key, subject, body, confidence} ->
      %{thread: thread, email: email} = Map.fetch!(threads, thread_key)

      Repo.insert!(%MessageDraft{
        organization_id: organization.id,
        created_by_id: user.id,
        contact_id: Map.fetch!(contacts, contact_key).id,
        email_thread_id: thread.id,
        source_email_id: email.id,
        message_type: :email,
        subject: subject,
        body: body,
        ai_generated: true,
        ai_model_used: "Konevo AI",
        ai_confidence: confidence,
        tone_preset: :professional,
        status: :pending
      })
    end)
  end
end
