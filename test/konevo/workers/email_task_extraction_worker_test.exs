defmodule Konevo.Workers.EmailTaskExtractionWorkerTest do
  use Konevo.DataCase, async: false

  import Konevo.Factory

  alias Konevo.Repo
  alias Konevo.Tasks.Task
  alias Konevo.Workers.EmailTaskExtractionWorker

  defp with_ai_response(response) do
    original = Application.fetch_env!(:konevo, :ai)

    Application.put_env(:konevo, :ai,
      provider: Konevo.AIMockProvider,
      models: %{
        fast: %{
          provider: :mock,
          model: "mock-fast",
          api_key: "test",
          response: Jason.encode!(response)
        },
        standard: %{provider: :mock, model: "mock-standard", api_key: "test"},
        premium: %{provider: :mock, model: "mock-premium", api_key: "test"}
      }
    )

    on_exit(fn -> Application.put_env(:konevo, :ai, original) end)
  end

  test "runs an active automatic email-to-task workflow" do
    with_ai_response(%{tasks: [%{title: "Call lead", confidence: 0.8}]})

    user = insert(:user)
    org = insert(:organization)
    _membership = insert(:membership, user: user, organization: org, role: :owner)

    sequence =
      insert(:automation_sequence,
        organization: org,
        created_by: user,
        status: :active,
        trigger_type: :inbound_email_received,
        trigger_config: %{"workflow_type" => "inbound_email_task", "mode" => "automatic"}
      )

    insert(:automation_rule, organization: org, sequence: sequence, action_type: :prepare_task)

    email =
      insert(:email,
        organization: org,
        thread: insert(:email_thread, organization: org),
        is_inbound: true
      )

    assert :ok =
             EmailTaskExtractionWorker.perform(%Oban.Job{
               args: %{
                 "email_id" => email.id,
                 "organization_id" => org.id,
                 "user_id" => user.id
               }
             })

    assert %Task{title: "Call lead", source_email_id: email_id} =
             Repo.get_by(Task, organization_id: org.id, source_email_id: email.id)

    assert email_id == email.id
  end

  test "returns an error when the job actor no longer has a scope" do
    assert {:error, :missing_scope} =
             EmailTaskExtractionWorker.perform(%Oban.Job{
               args: %{"email_id" => -1, "organization_id" => -1, "user_id" => -1}
             })
  end
end
