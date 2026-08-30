defmodule Konevo.Messaging.MessageDraft do
  use Ecto.Schema
  import Ecto.Changeset

  @message_types [:email, :sms]
  @statuses [:pending, :approved, :rejected, :sent]
  @tone_presets [:professional, :casual, :urgent, :apologetic]

  schema "message_drafts" do
    field :message_type, Ecto.Enum, values: @message_types
    field :subject, :string
    field :body, :string
    field :ai_generated, :boolean, default: false
    field :ai_model_used, :string
    field :ai_confidence, :float
    field :tone_preset, Ecto.Enum, values: @tone_presets
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :approved_at, :utc_datetime
    field :approval_changes, :string

    belongs_to :organization, Konevo.Accounts.Organization
    belongs_to :contact, Konevo.Contacts.Contact
    belongs_to :email_thread, Konevo.Inbox.EmailThread
    belongs_to :source_email, Konevo.Inbox.Email
    belongs_to :created_by, Konevo.Accounts.User
    belongs_to :approved_by, Konevo.Accounts.User
    belongs_to :sent_message, Konevo.Messaging.MessageSent

    timestamps(type: :utc_datetime)
  end

  def message_types, do: @message_types
  def statuses, do: @statuses
  def tone_presets, do: @tone_presets

  @doc false
  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [
      :message_type,
      :subject,
      :body,
      :ai_generated,
      :ai_model_used,
      :ai_confidence,
      :tone_preset,
      :status,
      :contact_id,
      :email_thread_id
    ])
    |> validate_required([:message_type, :body])
    |> validate_length(:body, min: 1)
    |> validate_number(:ai_confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end

  @doc false
  def approve_changeset(draft, user_id, edited_body \\ nil) do
    changes = %{
      status: :approved,
      approved_by_id: user_id,
      approved_at: DateTime.utc_now(:second)
    }

    changes =
      if edited_body && edited_body != draft.body,
        do: Map.merge(changes, %{body: edited_body, approval_changes: "Body edited by approver"}),
        else: changes

    cast(draft, changes, [:status, :approved_by_id, :approved_at, :body, :approval_changes])
  end

  @doc false
  def unapprove_changeset(draft) do
    change(draft, status: :pending, approved_by_id: nil, approved_at: nil)
  end

  @doc false
  def link_contact_and_unapprove_changeset(draft, contact_id) do
    change(draft,
      contact_id: contact_id,
      status: :pending,
      approved_by_id: nil,
      approved_at: nil
    )
  end

  @doc false
  def reject_changeset(draft) do
    cast(draft, %{status: :rejected}, [:status])
  end
end
