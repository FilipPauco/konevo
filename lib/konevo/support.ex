defmodule Konevo.Support do
  @moduledoc """
  Handles support requests from authenticated workspace users.
  """

  alias Konevo.Accounts.Scope
  alias Konevo.Inbox
  alias Konevo.Inbox.EmailIntegration
  alias Konevo.Repo
  alias Konevo.Support.Request

  import Ecto.Query, warn: false

  def support_email do
    Application.fetch_env!(:konevo, :support_email)
  end

  def change_support_request(attrs \\ %{}) do
    Request.changeset(%Request{}, attrs)
  end

  def deliver_support_request(%Scope{user: %{email: email}} = scope, attrs)
      when is_binary(email) do
    with {:ok, request} <- apply_request(attrs) do
      deliver(scope, request)
    end
  end

  def deliver_support_request(_scope, _attrs), do: {:error, :unauthorized}

  def topic_options do
    Request.topics()
  end

  defp apply_request(attrs) do
    %Request{}
    |> Request.changeset(attrs)
    |> Ecto.Changeset.apply_action(:insert)
  end

  defp deliver(scope, request) do
    with {:ok, integration} <- support_gmail_integration() do
      Inbox.send_system_message(integration, %{
        to: support_email(),
        subject: "Support request: #{request.subject}",
        body: support_request_body(scope, request)
      })
    end
  end

  defp support_gmail_integration do
    email = support_email()

    query =
      from(i in EmailIntegration,
        where: i.provider == :gmail,
        where: i.sync_enabled == true,
        where: i.email_address == ^email,
        order_by: [desc: i.is_primary, asc: i.inserted_at],
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :support_gmail_not_connected}
      integration -> {:ok, integration}
    end
  end

  defp support_request_body(scope, request) do
    """
    Support request

    Topic: #{request.topic}
    Subject: #{request.subject}
    From: #{scope.user.email}
    User ID: #{scope.user.id}
    Organization: #{organization_label(scope)}
    Role: #{role_label(scope)}
    Submitted at: #{submitted_at()}

    Message:
    #{request.message}
    """
  end

  defp organization_label(%Scope{org: %{id: id, name: name}}), do: "#{name} (##{id})"
  defp organization_label(_scope), do: "No organization"

  defp role_label(%Scope{membership: %{role: role}}), do: to_string(role)
  defp role_label(_scope), do: "unknown"

  defp submitted_at do
    DateTime.utc_now(:second)
    |> DateTime.to_iso8601()
  end
end
