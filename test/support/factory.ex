defmodule Konevo.Factory do
  @moduledoc false

  use ExMachina.Ecto, repo: Konevo.Repo

  alias Konevo.Accounts.{Membership, Organization, User}
  alias Konevo.AI.{CategorizationJob, Preference, Run, TaskExtraction}
  alias Konevo.Automation.{Execution, Rule, Sequence}
  alias Konevo.Companies.Company
  alias Konevo.Compliance.{AuditLog, Consent, SuppressionEntry}
  alias Konevo.Contacts.{Activity, Contact, Note}
  alias Konevo.Deals.{Deal, DealStage}
  alias Konevo.Inbox.{Email, EmailIntegration, EmailThread, ScheduledEmail}
  alias Konevo.Messaging.{MessageDraft, MessageSent}
  alias Konevo.Tasks.Task
  alias Konevo.Tasks.TaskDependency
  alias Konevo.Tasks.TaskType

  def user_factory do
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      confirmed_at: DateTime.utc_now(:second)
    }
  end

  def organization_factory do
    %Organization{
      name: sequence(:org_name, &"Org #{&1}"),
      slug: sequence(:org_slug, &"org-#{&1}")
    }
  end

  def membership_factory do
    %Membership{
      user: build(:user),
      organization: build(:organization),
      role: :owner
    }
  end

  def company_factory do
    %Company{
      name: sequence(:company_name, &"Company #{&1}"),
      slug: sequence(:company_slug, &"company-#{&1}"),
      user: build(:user),
      organization: build(:organization)
    }
  end

  def contact_factory do
    %Contact{
      first_name: sequence(:first_name, &"First#{&1}"),
      last_name: "Last",
      slug: sequence(:contact_slug, &"first#{&1}-last"),
      email: sequence(:contact_email, &"contact#{&1}@example.com"),
      status: :lead,
      user: build(:user),
      organization: build(:organization)
    }
  end

  def contact_note_factory do
    %Note{
      body: sequence(:note_body, &"Note body #{&1}"),
      is_internal: false,
      contact: build(:contact),
      organization: build(:organization),
      created_by: build(:user)
    }
  end

  def contact_activity_factory do
    %Activity{
      activity_type: :note_added,
      activity_date: DateTime.utc_now(:second),
      contact: build(:contact),
      organization: build(:organization)
    }
  end

  def deal_stage_factory do
    %DealStage{
      name: sequence(:stage_name, &"Stage #{&1}"),
      position: sequence(:stage_position, & &1),
      color: "#3B82F6",
      is_final: false,
      organization: build(:organization)
    }
  end

  def deal_factory do
    %Deal{
      title: sequence(:deal_title, &"Deal #{&1}"),
      slug: sequence(:deal_slug, &"deal-#{&1}"),
      value: Decimal.new("1000.00"),
      currency: "EUR",
      organization: build(:organization),
      contact: build(:contact),
      stage: build(:deal_stage),
      owner: build(:user),
      created_by: build(:user)
    }
  end

  def task_factory do
    %Task{
      title: sequence(:task_title, &"Task #{&1}"),
      due_date: DateTime.add(DateTime.utc_now(:second), 86_400),
      status: :open,
      priority: :normal,
      position: 0,
      organization: build(:organization),
      created_by: build(:user)
    }
  end

  def task_type_factory do
    %TaskType{
      name: sequence(:task_type_name, &"Task Type #{&1}"),
      icon: "icon-[tabler--menu-2]",
      color: "#2563eb",
      position: 0,
      is_parent_only: false,
      organization: build(:organization)
    }
  end

  def task_dependency_factory do
    %TaskDependency{
      organization: build(:organization),
      task: build(:task),
      depends_on_task: build(:task)
    }
  end

  def email_integration_factory do
    %EmailIntegration{
      provider: :gmail,
      email_address: sequence(:integration_email, &"inbox#{&1}@example.com"),
      is_primary: false,
      sync_enabled: true,
      organization: build(:organization),
      user: build(:user)
    }
  end

  def email_thread_factory do
    %EmailThread{
      subject: sequence(:thread_subject, &"Thread subject #{&1}"),
      is_unresolved: true,
      is_archived: false,
      is_favorite: false,
      has_attachments: false,
      participants: [],
      organization: build(:organization)
    }
  end

  def email_factory do
    %Email{
      message_id: sequence(:message_id, &"msg-#{&1}@mail.example.com"),
      from: sequence(:email_from, &"sender#{&1}@example.com"),
      to: ["recipient@example.com"],
      received_at: DateTime.utc_now(:second),
      is_inbound: true,
      has_attachments: false,
      organization: build(:organization),
      thread: build(:email_thread)
    }
  end

  def scheduled_email_factory do
    %ScheduledEmail{
      kind: :new_message,
      to: [sequence(:scheduled_email_to, &"scheduled#{&1}@example.com")],
      cc: [],
      bcc: [],
      subject: sequence(:scheduled_email_subject, &"Scheduled #{&1}"),
      body: sequence(:scheduled_email_body, &"Scheduled body #{&1}"),
      scheduled_at: DateTime.add(DateTime.utc_now(:second), 3600),
      status: :pending,
      organization: build(:organization),
      scheduled_by: build(:user)
    }
  end

  def message_sent_factory do
    %MessageSent{
      message_type: :email,
      recipient: sequence(:sent_recipient, &"recipient#{&1}@example.com"),
      body: sequence(:sent_body, &"Message body #{&1}"),
      status: :sent,
      sent_at: DateTime.utc_now(:second),
      is_manual: true,
      is_automation: false,
      organization: build(:organization),
      sent_by: build(:user)
    }
  end

  def message_draft_factory do
    %MessageDraft{
      message_type: :email,
      body: sequence(:draft_body, &"Draft body #{&1}"),
      ai_generated: false,
      status: :pending,
      organization: build(:organization),
      created_by: build(:user)
    }
  end

  def categorization_job_factory do
    %CategorizationJob{
      status: :pending,
      organization: build(:organization),
      email_thread: build(:email_thread)
    }
  end

  def task_extraction_factory do
    %TaskExtraction{
      extracted_tasks: [],
      extraction_confidence: 0.9,
      model_used: "gpt-4o",
      organization: build(:organization),
      email: build(:email)
    }
  end

  def ai_run_factory do
    %Run{
      kind: "reply_draft",
      status: :completed,
      input: %{},
      output: %{},
      organization: build(:organization),
      user: build(:user)
    }
  end

  def ai_preference_factory do
    %Preference{
      tone: "professional",
      language: "English",
      response_length: "concise",
      organization: build(:organization),
      user: build(:user)
    }
  end

  def consent_factory do
    %Consent{
      channel: :email,
      status: :granted,
      source: :manual,
      granted_at: DateTime.utc_now(:second),
      organization: build(:organization),
      contact: build(:contact)
    }
  end

  def suppression_entry_factory do
    %SuppressionEntry{
      channel: :email,
      value: sequence(:suppression_value, &"blocked#{&1}@example.com"),
      reason: :unsubscribed,
      organization: build(:organization)
    }
  end

  def audit_log_factory do
    %AuditLog{
      action: "contact.created",
      resource_type: "contact",
      resource_id: sequence(:audit_resource_id, & &1),
      metadata: %{},
      organization: build(:organization),
      actor: build(:user)
    }
  end

  def automation_sequence_factory do
    %Sequence{
      name: sequence(:sequence_name, &"Sequence #{&1}"),
      status: :draft,
      trigger_type: :manual,
      trigger_config: %{},
      organization: build(:organization),
      created_by: build(:user)
    }
  end

  def automation_rule_factory do
    %Rule{
      position: 0,
      action_type: :send_email,
      action_config: %{subject: "Hello", body: "Welcome"},
      delay_seconds: 0,
      organization: build(:organization),
      sequence: build(:automation_sequence)
    }
  end

  def automation_execution_factory do
    %Execution{
      status: :pending,
      enrolled_at: DateTime.utc_now(:second),
      metadata: %{},
      organization: build(:organization),
      sequence: build(:automation_sequence),
      contact: build(:contact)
    }
  end
end
