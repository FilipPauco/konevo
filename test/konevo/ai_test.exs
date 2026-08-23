defmodule Konevo.AITest do
  use Konevo.DataCase, async: false

  import Konevo.Factory

  alias Konevo.Accounts.Scope
  alias Konevo.AI
  alias Konevo.AI.{CategorizationJob, Preference, Run, TaskExtraction}
  alias Konevo.Repo

  defp build_scope do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: :owner)
    Scope.for_user_in_org(user, org, membership)
  end

  defp thread_for(scope) do
    insert(:email_thread, organization: scope.org)
  end

  defp email_for(scope) do
    thread = thread_for(scope)
    insert(:email, organization: scope.org, thread: thread)
  end

  defp with_ai_response(response, tier \\ :fast) do
    original = Application.fetch_env!(:konevo, :ai)
    response = if is_binary(response), do: response, else: Jason.encode!(response)

    Application.put_env(:konevo, :ai,
      provider: Konevo.AIMockProvider,
      models: %{
        fast: %{
          provider: :mock,
          model: "mock-fast",
          api_key: "test",
          test_pid: self(),
          response: if(tier == :fast, do: response)
        },
        standard: %{
          provider: :mock,
          model: "mock-standard",
          api_key: "test",
          test_pid: self(),
          response: if(tier == :standard, do: response)
        },
        premium: %{provider: :mock, model: "mock-premium", api_key: "test"}
      }
    )

    on_exit(fn -> Application.put_env(:konevo, :ai, original) end)
  end

  # ---------------------------------------------------------------------------
  # enqueue_categorization/1
  # ---------------------------------------------------------------------------

  describe "enqueue_categorization/1" do
    test "creates a pending job for the thread" do
      scope = build_scope()
      thread = thread_for(scope)

      assert {:ok, %CategorizationJob{status: :pending}} = AI.enqueue_categorization(thread)
    end

    test "returns existing job when one is already pending" do
      scope = build_scope()
      thread = thread_for(scope)

      {:ok, first} = AI.enqueue_categorization(thread)
      {:ok, second} = AI.enqueue_categorization(thread)

      assert first.id == second.id
    end

    test "returns existing job when one is processing" do
      scope = build_scope()
      thread = thread_for(scope)

      {:ok, job} = AI.enqueue_categorization(thread)
      {:ok, _} = AI.mark_processing(job)
      {:ok, idempotent} = AI.enqueue_categorization(thread)

      assert job.id == idempotent.id
    end

    test "creates a new job when previous one completed" do
      scope = build_scope()
      thread = thread_for(scope)

      {:ok, job} = AI.enqueue_categorization(thread)
      AI.complete_categorization(job, :lead, 0.95)

      {:ok, new_job} = AI.enqueue_categorization(thread)
      refute job.id == new_job.id
    end
  end

  # ---------------------------------------------------------------------------
  # mark_processing/1
  # ---------------------------------------------------------------------------

  describe "mark_processing/1" do
    test "sets status to processing" do
      scope = build_scope()
      thread = thread_for(scope)
      {:ok, job} = AI.enqueue_categorization(thread)

      assert {:ok, updated} = AI.mark_processing(job)
      assert updated.status == :processing
    end
  end

  # ---------------------------------------------------------------------------
  # complete_categorization/3
  # ---------------------------------------------------------------------------

  describe "complete_categorization/3" do
    test "sets status to completed with category and confidence" do
      scope = build_scope()
      thread = thread_for(scope)
      {:ok, job} = AI.enqueue_categorization(thread)

      assert {:ok, completed} = AI.complete_categorization(job, :lead, 0.91)
      assert completed.status == :completed
      assert completed.result_category == :lead
      assert completed.confidence_score == 0.91
      assert completed.processed_at != nil
    end

    test "updates the email thread category" do
      scope = build_scope()
      thread = thread_for(scope)
      {:ok, job} = AI.enqueue_categorization(thread)

      AI.complete_categorization(job, :customer, 0.85)

      updated_thread = Konevo.Repo.get!(Konevo.Inbox.EmailThread, thread.id)
      assert updated_thread.category == :customer
    end
  end

  # ---------------------------------------------------------------------------
  # fail_categorization/2
  # ---------------------------------------------------------------------------

  describe "fail_categorization/2" do
    test "sets status to failed with error message" do
      scope = build_scope()
      thread = thread_for(scope)
      {:ok, job} = AI.enqueue_categorization(thread)

      assert {:ok, failed} = AI.fail_categorization(job, "OpenAI timeout")
      assert failed.status == :failed
      assert failed.error_message == "OpenAI timeout"
      assert failed.processed_at != nil
    end
  end

  # ---------------------------------------------------------------------------
  # list_categorization_jobs/1
  # ---------------------------------------------------------------------------

  describe "list_categorization_jobs/1" do
    test "returns all jobs for the thread ordered newest first" do
      scope = build_scope()
      thread = thread_for(scope)

      {:ok, j1} = AI.enqueue_categorization(thread)
      AI.complete_categorization(j1, :lead, 0.9)
      {:ok, j2} = AI.enqueue_categorization(thread)

      jobs = AI.list_categorization_jobs(thread)
      ids = Enum.map(jobs, & &1.id)

      assert j1.id in ids
      assert j2.id in ids
    end
  end

  # ---------------------------------------------------------------------------
  # latest_categorization/1
  # ---------------------------------------------------------------------------

  describe "latest_categorization/1" do
    test "returns the most recent completed job" do
      scope = build_scope()
      thread = thread_for(scope)

      {:ok, j1} = AI.enqueue_categorization(thread)
      {:ok, completed} = AI.complete_categorization(j1, :lead, 0.9)

      result = AI.latest_categorization(thread)
      assert result.id == completed.id
    end

    test "returns nil when no completed job exists" do
      scope = build_scope()
      thread = thread_for(scope)
      {:ok, _job} = AI.enqueue_categorization(thread)

      assert AI.latest_categorization(thread) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # categorization_job_counts/1
  # ---------------------------------------------------------------------------

  describe "categorization_job_counts/1" do
    test "returns counts grouped by status" do
      scope = build_scope()
      thread1 = thread_for(scope)
      thread2 = thread_for(scope)

      {:ok, j1} = AI.enqueue_categorization(thread1)
      {:ok, j2} = AI.enqueue_categorization(thread2)
      AI.complete_categorization(j1, :lead, 0.9)
      AI.fail_categorization(j2, "error")

      counts = AI.categorization_job_counts(scope.org.id)

      assert counts[:completed] == 1
      assert counts[:failed] == 1
    end
  end

  # ---------------------------------------------------------------------------
  # store_extraction/4
  # ---------------------------------------------------------------------------

  describe "store_extraction/4" do
    test "stores extracted tasks for an email" do
      scope = build_scope()
      email = email_for(scope)

      tasks = [
        %{"title" => "Send proposal", "due_date" => "2026-06-27", "confidence" => 0.88}
      ]

      assert {:ok, %TaskExtraction{extraction_confidence: 0.88}} =
               AI.store_extraction(email, tasks, 0.88, "gpt-4o")
    end

    test "associates with email and org" do
      scope = build_scope()
      email = email_for(scope)

      {:ok, extraction} = AI.store_extraction(email, [], 0.7, "gpt-4o")
      assert extraction.email_id == email.id
      assert extraction.organization_id == scope.org.id
    end

    test "creates a new record each call (not idempotent by design)" do
      scope = build_scope()
      email = email_for(scope)

      {:ok, e1} = AI.store_extraction(email, [], 0.7, "gpt-4o")
      {:ok, e2} = AI.store_extraction(email, [], 0.8, "gpt-4o")

      refute e1.id == e2.id
    end

    test "returns error changeset when confidence is out of range" do
      scope = build_scope()
      email = email_for(scope)

      assert {:error, %Ecto.Changeset{}} = AI.store_extraction(email, [], 1.5, "gpt-4o")
    end
  end

  # ---------------------------------------------------------------------------
  # latest_extraction/1
  # ---------------------------------------------------------------------------

  describe "latest_extraction/1" do
    test "returns the most recent extraction for an email" do
      scope = build_scope()
      email = email_for(scope)

      {:ok, _e1} = AI.store_extraction(email, [], 0.7, "gpt-4o")
      {:ok, e2} = AI.store_extraction(email, [], 0.9, "gpt-4o-mini")

      result = AI.latest_extraction(email)
      assert result.id == e2.id
    end

    test "returns nil when no extractions exist" do
      scope = build_scope()
      email = email_for(scope)

      assert AI.latest_extraction(email) == nil
    end
  end

  describe "extract_tasks_from_email/3" do
    test "calls the fast model and stores extracted task suggestions" do
      with_ai_response(%{
        tasks: [
          %{
            title: "Send pricing",
            description: "Customer asked for updated pricing.",
            due_date: "2026-08-01",
            priority: "high",
            confidence: 0.92
          }
        ]
      })

      scope = build_scope()
      email = insert(:email, organization: scope.org, thread: thread_for(scope), body: "Pricing?")

      assert {:ok, _preference} =
               AI.update_preference(scope, %{
                 workspace_context: "Company XYZ sells custom furniture to B2B buyers."
               })

      assert {:ok, %{tasks: [task], extraction: extraction, run: run}} =
               AI.extract_tasks_from_email(scope, email, %{
                 "instructions" => "Only extract sales follow-ups."
               })

      assert_received {:ai_complete, :entity_extraction, messages}
      assert [%{role: :system}, %{role: :user, content: content}] = messages
      assert List.first(messages).content =~ "Company XYZ sells custom furniture"
      assert content =~ "Only extract sales follow-ups."
      assert task["title"] == "Send pricing"
      assert extraction.model_used == "mock-fast"
      assert extraction.extraction_confidence == 0.92
      assert run.status == :completed
      assert run.kind == "entity_extraction"
    end

    test "fails safely for malformed model output" do
      with_ai_response("this is not JSON")
      scope = build_scope()
      email = email_for(scope)

      assert {:error, :invalid_task_extraction} = AI.extract_tasks_from_email(scope, email)

      assert %Run{status: :failed, error_message: ":invalid_task_extraction"} =
               Repo.get_by(Run, organization_id: scope.org.id, kind: "entity_extraction")

      assert AI.latest_extraction(email) == nil
    end

    test "stores an empty extraction when no actionable tasks are returned" do
      with_ai_response(%{tasks: []})
      scope = build_scope()
      email = email_for(scope)

      assert {:ok, %{tasks: [], extraction: extraction, run: %Run{status: :completed}}} =
               AI.extract_tasks_from_email(scope, email)

      assert extraction.extracted_tasks == []
      assert extraction.extraction_confidence == 0.0
    end

    test "normalizes invalid task fields and discards entries without a title" do
      with_ai_response(%{
        tasks: [
          %{description: "Missing a title", confidence: 0.8},
          %{title: "  Follow up ", description: " ", priority: "unknown", confidence: 2.0},
          "not a task"
        ]
      })

      scope = build_scope()
      email = email_for(scope)

      assert {:ok, %{tasks: [task]}} = AI.extract_tasks_from_email(scope, email)

      assert task == %{
               "title" => "Follow up",
               "description" => nil,
               "due_date" => nil,
               "priority" => "normal",
               "confidence" => 1.0
             }
    end
  end

  describe "reply drafts" do
    test "uses a grounded prompt and returns safe email paragraphs" do
      with_ai_response(
        "Dobrý deň,\n\nOverím dostupnosť produktu <M> a ozvem sa.\n\nS pozdravom,",
        :standard
      )

      scope = build_scope()
      thread = thread_for(scope)

      assert {:ok, _preference} =
               AI.update_preference(scope, %{
                 workspace_context: "This inbox is for Company XYZ product inquiries.",
                 email_instructions: "Keep replies under five sentences and avoid hype."
               })

      insert(:email,
        organization: scope.org,
        thread: thread,
        from: "buyer@example.com",
        subject: "Black football T-shirt",
        body: "Is the black football T-shirt in size M available?"
      )

      thread = Konevo.Inbox.get_thread!(scope, thread.id)

      assert {:ok, %{content: content, run: %Run{kind: "reply_draft", status: :completed}}} =
               AI.generate_reply_draft(scope, thread)

      assert content ==
               "<p>Dobrý deň,</p><p>Overím dostupnosť produktu &lt;M&gt; a ozvem sa.</p><p>S pozdravom,</p>"

      assert_received {:ai_complete, :reply_draft,
                       [%{content: instructions}, %{content: context}]}

      assert instructions =~ "Never invent or assume facts beyond those sources"
      assert instructions =~ "Do not offer a meeting"
      assert instructions =~ "reply in the language of the latest customer email"
      assert instructions =~ "Company XYZ product inquiries"
      assert instructions =~ "Keep replies under five sentences"
      assert context =~ "black football T-shirt"
    end

    test "includes the user's requested outcome and tone in the draft prompt" do
      with_ai_response("Hello,\n\nI will be available from Monday.\n\nBest regards,", :standard)

      scope = build_scope()
      thread = thread_for(scope)

      assert {:ok, %{run: %Run{input: input}}} =
               AI.generate_reply_draft(scope, thread, %{
                 instruction: "Decline politely and say I am available from Monday.",
                 tone: "warm"
               })

      assert input["user_instruction"] == "Decline politely and say I am available from Monday."
      assert input["requested_tone"] == "warm"

      assert_received {:ai_complete, :reply_draft, [%{content: instructions}, _context]}

      assert instructions =~ "Decline politely and say I am available from Monday."
      assert instructions =~ "TRUSTED REPLY BRIEF FROM THE USER"
      assert instructions =~ "MUST clearly communicate each concrete decision"

      assert instructions =~
               "do not omit, weaken, replace, or turn a clear answer into \"I will check\""

      assert instructions =~ "use a warm tone"
    end
  end

  # ---------------------------------------------------------------------------
  # Assistant preferences
  # ---------------------------------------------------------------------------

  describe "assistant preferences" do
    test "creates defaults for the current user" do
      scope = build_scope()

      assert {:ok,
              %Preference{tone: "professional", language: "auto", response_length: "concise"}} =
               AI.get_preference(scope)
    end

    test "updates the current user's response preferences" do
      scope = build_scope()

      assert {:ok, %Preference{tone: "warm", language: "Slovak"}} =
               AI.update_preference(scope, %{
                 tone: "warm",
                 language: "Slovak",
                 response_length: "detailed",
                 custom_instruction: "Use a helpful, direct style.",
                 workspace_context: "User applies for jobs from this inbox.",
                 email_instructions: "Be concise in emails."
               })

      assert {:ok, preference} = AI.get_preference(scope)
      assert preference.workspace_context == "User applies for jobs from this inbox."
      assert preference.email_instructions == "Be concise in emails."
    end

    test "rejects unsupported preference values" do
      scope = build_scope()

      assert {:error, changeset} = AI.update_preference(scope, %{tone: "casual"})
      assert errors_on(changeset).tone != []
    end
  end

  describe "provider settings" do
    test "encrypts and decrypts provider API keys" do
      scope = build_scope()

      assert {:ok, setting} =
               AI.update_provider_setting(scope, %{
                 "provider" => "openai_responses",
                 "api_key" => "sk-test-123456",
                 "monthly_budget" => "25.50"
               })

      assert setting.api_key_last4 == "3456"
      refute setting.encrypted_api_key =~ "sk-test"
      assert Decimal.equal?(setting.monthly_budget, Decimal.new("25.50"))
      assert {:ok, "sk-test-123456"} = AI.fetch_provider_api_key(scope, :openai_responses)

      [summary | _rest] = AI.provider_usage_summary(scope)
      assert summary.api_key_mask == "sk-*****"
    end

    test "summarizes month-to-date usage by OpenAI model" do
      scope = build_scope()

      assert {:ok, _setting} =
               AI.update_provider_setting(scope, %{
                 "provider" => "openai_responses",
                 "api_key" => "sk-test-123456",
                 "monthly_budget" => "50.00"
               })

      insert(:ai_run,
        organization: scope.org,
        user: scope.user,
        provider: "openai_responses",
        model_used: "gpt-5.6-terra",
        input_tokens: 1_000_000,
        output_tokens: 1_000_000
      )

      insert(:ai_run,
        organization: scope.org,
        user: scope.user,
        provider: "openai_responses",
        model_used: "gpt-5.6-luna",
        input_tokens: 2_000_000,
        output_tokens: 1_000_000
      )

      [openai] = AI.provider_usage_summary(scope, ~D[2026-07-29])
      [terra, luna] = AI.model_usage_summary(scope, ~D[2026-07-29])

      assert openai.provider == :openai_responses
      assert openai.has_api_key?
      assert openai.api_key_mask == "sk-*****"
      assert openai.total_tokens == 5_000_000
      assert openai.runs == 2
      assert Decimal.equal?(openai.estimated_spend, Decimal.new("15.6000"))
      assert Decimal.equal?(openai.monthly_budget, Decimal.new("50.00"))

      assert terra.model == "gpt-5.6-terra"
      assert terra.total_tokens == 2_000_000
      assert Decimal.equal?(terra.estimated_spend, Decimal.new("14.0000"))
      assert luna.model == "gpt-5.6-luna"
      assert luna.total_tokens == 3_000_000
      assert Decimal.equal?(luna.estimated_spend, Decimal.new("1.6000"))
    end
  end

  # ---------------------------------------------------------------------------
  # Schema validations
  # ---------------------------------------------------------------------------

  describe "CategorizationJob.changeset/2" do
    test "defaults status to pending" do
      job = %CategorizationJob{}
      assert job.status == :pending
    end

    test "rejects confidence outside 0.0-1.0" do
      changeset =
        CategorizationJob.changeset(%CategorizationJob{}, %{
          status: :pending,
          confidence_score: 2.0
        })

      assert errors_on(changeset).confidence_score != []
    end
  end

  describe "TaskExtraction.changeset/2" do
    test "requires extracted_tasks, extraction_confidence, model_used" do
      changeset = TaskExtraction.changeset(%TaskExtraction{}, %{})
      assert "can't be blank" in errors_on(changeset).extraction_confidence
      assert "can't be blank" in errors_on(changeset).model_used
    end

    test "rejects confidence outside 0.0-1.0" do
      changeset =
        TaskExtraction.changeset(%TaskExtraction{}, %{
          extracted_tasks: [],
          extraction_confidence: -0.1,
          model_used: "gpt-4o"
        })

      assert errors_on(changeset).extraction_confidence != []
    end
  end
end
