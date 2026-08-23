defmodule KonevoWeb.InboxLive.IndexTest do
  use KonevoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Konevo.Factory
  import Konevo.InboxFixtures

  alias Konevo.Inbox
  alias Konevo.Inbox.ScheduledEmail
  alias Konevo.Repo

  defp org_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}

  test "silently redirects unauthenticated visitors home" do
    org = insert(:organization)

    {:error, {:redirect, %{to: path}}} =
      build_conn()
      |> org_conn(org)
      |> live(~p"/inbox")

    assert path == "/"
  end

  describe "index mount" do
    setup :register_and_log_in_user_with_org

    test "renders a loader while threads load", %{conn: conn, org: org} do
      document =
        conn
        |> org_conn(org)
        |> get(~p"/inbox")
        |> html_response(200)
        |> LazyHTML.from_fragment()

      assert document |> LazyHTML.query("#inbox-threads-loading[aria-busy='true']") |> Enum.any?()
      refute document |> LazyHTML.query("#threads-empty") |> Enum.any?()
      refute document |> LazyHTML.query("#inbox-threads") |> Enum.any?()
    end

    test "shows the empty state after async load finishes", %{conn: conn, org: org} do
      {:ok, view, html} =
        conn
        |> org_conn(org)
        |> live(~p"/inbox")

      document = LazyHTML.from_fragment(html)

      assert document |> LazyHTML.query("#inbox-threads-loading[aria-busy='true']") |> Enum.any?()
      refute document |> LazyHTML.query("#threads-empty") |> Enum.any?()

      document =
        view
        |> render_async(1000)
        |> LazyHTML.from_fragment()

      assert document |> LazyHTML.query("#threads-empty") |> Enum.any?()
      refute document |> LazyHTML.query("#inbox-threads-loading") |> Enum.any?()
    end

    test "streams threads after async load finishes", %{conn: conn, org: org, scope: scope} do
      thread =
        thread_fixture(scope, %{
          subject: "Async inbox thread",
          snippet: "Thread loaded from the async stream",
          participants: ["buyer@example.com"]
        })

      {:ok, view, _html} =
        conn
        |> org_conn(org)
        |> live(~p"/inbox")

      _html = render_async(view, 1000)

      assert has_element?(view, "#inbox-threads")
      assert has_element?(view, "#thread-select-#{thread.id}")

      document =
        view
        |> render()
        |> LazyHTML.from_fragment()

      assert [empty_state_class] =
               document
               |> LazyHTML.query("#threads-empty")
               |> LazyHTML.attribute("class")

      assert empty_state_class =~ "hidden"
      assert empty_state_class =~ "only:flex"
    end

    test "shows a thread message count when replies exist", %{conn: conn, org: org, scope: scope} do
      thread = thread_fixture(scope, %{subject: "Counted thread"})
      email_fixture(scope, thread)
      email_fixture(scope, thread)

      {:ok, view, _html} =
        conn
        |> org_conn(org)
        |> live(~p"/inbox")

      _html = render_async(view, 1000)

      assert has_element?(view, "#thread-message-count-#{thread.id}")
    end

    test "shows clean sender name and keeps full address in tooltip", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      thread =
        thread_fixture(scope, %{
          subject: "Sender display",
          participants: [
            "Example Sender <sender@example.com>",
            scope.user.email
          ]
        })

      {:ok, view, _html} =
        conn
        |> org_conn(org)
        |> live(~p"/inbox")

      html = render_async(view, 1000)

      assert has_element?(view, "#thread-sender-#{thread.id}")

      assert has_element?(
               view,
               ".sender-info-trigger[data-sender-details='sender@example.com']"
             )

      assert html =~ "Example Sender"
      assert html =~ "sender@example.com"
      refute html =~ "Example Sender &lt;sender@example.com&gt;"
    end

    test "uses the connected Gmail mailbox to identify the other participant", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      integration_fixture(scope, %{provider: :gmail, email_address: "mailbox@example.com"})

      _thread =
        thread_fixture(scope, %{
          subject: "Sent thread",
          participants: ["mailbox@example.com", "Other Person <other@example.com>"]
        })

      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/inbox")
      html = render_async(view, 1000)

      assert html =~ "me, Other Person"
      assert has_element?(view, ".sender-info-trigger[data-sender-details='other@example.com']")
      refute html =~ "me, mailbox"
    end

    test "shows compose schedule controls", %{conn: conn, org: org} do
      {:ok, view, _html} =
        conn
        |> org_conn(org)
        |> live(~p"/inbox")

      view
      |> element("button[phx-click='open_compose']")
      |> render_click()

      assert has_element?(view, "#compose-form")
      assert has_element?(view, "#compose-schedule-menu")
      assert has_element?(view, "#compose_scheduled_at")
    end

    test "shows recipient validation errors before sending", %{conn: conn, org: org} do
      {:ok, view, _html} =
        conn
        |> org_conn(org)
        |> live(~p"/inbox")

      view
      |> element("button[phx-click='open_compose']")
      |> render_click()

      view
      |> render_submit("send_message", %{
        "compose" => %{
          "to" => "buyer@example.com",
          "cc" => "not-an-email",
          "bcc" => "",
          "subject" => "Question",
          "body" => "Hello"
        }
      })

      assert has_element?(view, "#compose_cc[aria-invalid='true']")
      assert has_element?(view, "#compose_cc-error")
      refute render(view) =~ "Failed to send message"
    end

    test "shows an inline body error before sending an empty message", %{conn: conn, org: org} do
      {:ok, view, _html} =
        conn
        |> org_conn(org)
        |> live(~p"/inbox")

      view
      |> element("button[phx-click='open_compose']")
      |> render_click()

      view
      |> render_submit("send_message", %{
        "compose" => %{
          "to" => "buyer@example.com",
          "cc" => "",
          "bcc" => "",
          "subject" => "Question",
          "body" => ""
        }
      })

      assert has_element?(view, "#compose-body-wrapper")
      assert render(view) =~ "Write a message before sending"
      refute render(view) =~ "Failed to send message"
    end

    test "shows an inline recipient error before sending without a recipient", %{
      conn: conn,
      org: org
    } do
      {:ok, view, _html} =
        conn
        |> org_conn(org)
        |> live(~p"/inbox")

      view
      |> element("button[phx-click='open_compose']")
      |> render_click()

      view
      |> render_submit("send_message", %{
        "compose" => %{
          "to" => "",
          "cc" => "",
          "bcc" => "",
          "subject" => "Question",
          "body" => "Hello"
        }
      })

      assert has_element?(view, "#compose_to[aria-invalid='true']")
      assert render(view) =~ "Add at least one recipient"
      refute render(view) =~ "Failed to send message"
    end

    test "refresh enqueues an immediate Gmail sync", %{conn: conn, org: org, scope: scope} do
      integration = integration_fixture(scope, %{sync_enabled: true})

      {:ok, view, _html} =
        conn
        |> org_conn(org)
        |> live(~p"/inbox")

      _html = render_async(view, 1000)

      view
      |> element("#inbox-refresh")
      |> render_click()

      assert has_element?(view, "#inbox-refresh[disabled] .animate-spin")

      assert [
               %Oban.Job{
                 worker: "Konevo.Workers.GmailSyncWorker",
                 args: %{"integration_id" => integration_id}
               }
             ] = Repo.all(Oban.Job)

      assert integration_id == integration.id
    end

    test "suggests contact recipients while composing", %{
      conn: conn,
      org: org,
      user: user
    } do
      company = insert(:company, name: "Acme Labs", user: user, organization: org)

      contact =
        insert(:contact,
          first_name: "Alice",
          last_name: "Buyer",
          email: "alice@acme.test",
          company: company,
          user: user,
          organization: org
        )

      other_org = insert(:organization)
      other_user = insert(:user)

      _hidden =
        insert(:contact,
          first_name: "Alice",
          email: "hidden@acme.test",
          user: other_user,
          organization: other_org
        )

      {:ok, view, _html} =
        conn
        |> org_conn(org)
        |> live(~p"/inbox")

      view
      |> element("button[phx-click='open_compose']")
      |> render_click()

      view
      |> element("#compose-form")
      |> render_change(%{
        "_target" => ["compose", "cc"],
        "compose" => %{"to" => "", "cc" => "acm", "bcc" => "", "subject" => "", "body" => ""}
      })

      assert has_element?(view, "#compose-cc-suggestions")
      assert has_element?(view, "#compose-recipient-suggestion-cc-#{contact.id}")
      refute render(view) =~ "hidden@acme.test"

      view
      |> element("#compose-recipient-suggestion-cc-#{contact.id}")
      |> render_click()

      assert has_element?(view, "#compose_cc[value='alice@acme.test, ']")
      refute has_element?(view, "#compose-cc-suggestions")
    end

    test "scheduled view shows pending scheduled email and cancels it", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      scheduled_email =
        insert(:scheduled_email,
          organization: org,
          scheduled_by: scope.user,
          subject: "Follow up later",
          to: ["buyer@example.com"]
        )

      {:ok, view, _html} =
        conn
        |> org_conn(org)
        |> live(~p"/inbox?view=scheduled")

      _html = render_async(view, 1000)

      assert has_element?(view, "#scheduled-email-cancel-#{scheduled_email.id}")

      view
      |> element("#scheduled-email-cancel-#{scheduled_email.id}")
      |> render_click()

      assert Repo.get!(ScheduledEmail, scheduled_email.id).status == :cancelled
    end

    test "select all uses one checkbox and syncs visible row selection", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      first = thread_fixture(scope, %{subject: "First selectable thread"})
      second = thread_fixture(scope, %{subject: "Second selectable thread"})

      {:ok, view, _html} =
        conn
        |> org_conn(org)
        |> live(~p"/inbox")

      _html = render_async(view, 1000)

      assert has_element?(view, "#inbox-select-all")
      refute has_element?(view, "#select-dropdown")

      view
      |> element("#inbox-select-all")
      |> render_click()

      assert_push_event(view, "inbox-thread-selection", %{ids: selected_ids})
      assert Enum.sort(selected_ids) == Enum.sort([to_string(first.id), to_string(second.id)])
      assert has_element?(view, "#inbox-select-all[checked]")
    end

    test "filters threads by category", %{conn: conn, org: org, scope: scope} do
      lead = thread_fixture(scope, %{subject: "Lead thread", category: :lead})
      support = thread_fixture(scope, %{subject: "Support thread", category: :support})

      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/inbox")
      _html = render_async(view, 1000)

      view
      |> element("#inbox-tab-lead")
      |> render_click()

      _html = render_async(view, 1000)

      assert has_element?(view, "#thread-select-#{lead.id}")
      refute has_element?(view, "#thread-select-#{support.id}")
    end

    test "stars and categorizes a thread from the inbox list", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      thread = thread_fixture(scope, %{subject: "Categorize thread"})

      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/inbox")
      _html = render_async(view, 1000)

      view
      |> element("#thread-star-#{thread.id}")
      |> render_click()

      assert Inbox.get_thread!(scope, thread.id).is_favorite

      view
      |> element("#thread-category-#{thread.id} button[phx-value-category='customer']")
      |> render_click()

      assert Inbox.get_thread!(scope, thread.id).category == :customer
    end

    test "archives selected threads in bulk", %{conn: conn, org: org, scope: scope} do
      selected = thread_fixture(scope, %{subject: "Archive selected"})
      unselected = thread_fixture(scope, %{subject: "Keep active"})

      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/inbox")
      _html = render_async(view, 1000)

      view
      |> element("#thread-select-#{selected.id}")
      |> render_click()

      view
      |> element("button[phx-click='bulk_action'][phx-value-action='archive']")
      |> render_click()

      assert Inbox.get_thread!(scope, selected.id).is_archived
      refute Inbox.get_thread!(scope, unselected.id).is_archived
    end

    test "searches and filters unresolved threads", %{conn: conn, org: org, scope: scope} do
      match = thread_fixture(scope, %{subject: "Important unresolved", is_unresolved: true})
      resolved = thread_fixture(scope, %{subject: "Important resolved", is_unresolved: false})
      miss = thread_fixture(scope, %{subject: "Other thread", is_unresolved: true})

      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/inbox")
      _html = render_async(view, 1000)

      view
      |> form("#inbox-search-form", q: "Important")
      |> render_submit()

      _html = render_async(view, 1000)
      assert has_element?(view, "#thread-select-#{match.id}")
      assert has_element?(view, "#thread-select-#{resolved.id}")
      refute has_element?(view, "#thread-select-#{miss.id}")

      view
      |> render_hook("filter_unresolved", %{"value" => "true"})

      _html = render_async(view, 1000)
      assert has_element?(view, "#thread-select-#{match.id}")
      refute has_element?(view, "#thread-select-#{resolved.id}")
    end
  end
end
