defmodule Konevo.Inbox.ScheduledEmail do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds [:new_message, :reply]
  @statuses [:pending, :sent, :cancelled, :failed]

  schema "scheduled_emails" do
    field(:kind, Ecto.Enum, values: @kinds)
    field(:to, {:array, :string}, default: [])
    field(:cc, {:array, :string}, default: [])
    field(:bcc, {:array, :string}, default: [])
    field(:subject, :string)
    field(:body, :string)
    field(:in_reply_to, :string)
    field(:gmail_thread_id, :string)
    field(:attachment_owner_id, :string)
    field(:attachment_ids, {:array, :integer}, default: [])
    field(:scheduled_at, :utc_datetime)
    field(:sent_at, :utc_datetime)
    field(:cancelled_at, :utc_datetime)
    field(:failed_at, :utc_datetime)
    field(:status, Ecto.Enum, values: @statuses, default: :pending)
    field(:external_message_id, :string)
    field(:failure_reason, :string)

    belongs_to(:organization, Konevo.Accounts.Organization)
    belongs_to(:scheduled_by, Konevo.Accounts.User)
    belongs_to(:email_thread, Konevo.Inbox.EmailThread)
    belongs_to(:oban_job, Oban.Job)

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def statuses, do: @statuses

  @doc false
  def changeset(scheduled_email, attrs) do
    scheduled_email
    |> cast(attrs, [
      :kind,
      :to,
      :cc,
      :bcc,
      :subject,
      :body,
      :in_reply_to,
      :gmail_thread_id,
      :attachment_owner_id,
      :attachment_ids,
      :scheduled_at,
      :sent_at,
      :cancelled_at,
      :failed_at,
      :status,
      :external_message_id,
      :failure_reason,
      :email_thread_id,
      :oban_job_id
    ])
    |> validate_required([:kind, :body, :scheduled_at, :status])
    |> validate_length(:body, min: 1)
    |> validate_length(:subject, max: 998)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_recipients()
    |> validate_future_schedule()
  end

  defp validate_recipients(changeset) do
    if get_field(changeset, :to, []) == [] do
      add_error(changeset, :to, "must include at least one recipient")
    else
      changeset
    end
  end

  defp validate_future_schedule(changeset) do
    case get_field(changeset, :scheduled_at) do
      %DateTime{} = scheduled_at ->
        if DateTime.compare(scheduled_at, DateTime.utc_now(:second)) == :gt do
          changeset
        else
          add_error(changeset, :scheduled_at, "must be in the future")
        end

      _ ->
        changeset
    end
  end
end
