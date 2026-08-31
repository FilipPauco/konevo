defmodule KonevoWeb.SettingsLiveTest do
  use KonevoWeb.ConnCase, async: false

  alias Konevo.Accounts
  alias Konevo.AI
  alias Konevo.Inbox
  alias Konevo.Repo

  import Phoenix.LiveViewTest
  import Konevo.AccountsFixtures
  import Konevo.Factory
  import Konevo.InboxFixtures

  describe "mount" do
    setup :register_and_log_in_user_with_org

    test "renders settings tabs", %{conn: conn, org: org} do
      conn = %{conn | host: "#{org.slug}.localhost"}

      {:ok, view, _html} = live(conn, ~p"/settings")

      assert has_element?(view, "#settings-tabs")
      assert has_element?(view, "#settings-tab-mobile-form")
      assert has_element?(view, "#settings-tab-mobile-select")

      assert has_element?(
               view,
               "#settings-tab-mobile-select input[name='settings_tab[tab_text_input]']"
             )

      assert has_element?(view, "#settings-panel-general")
      assert has_element?(view, "#settings-tab-appearance")
      assert has_element?(view, "#settings-tab-profile")
      assert has_element?(view, "#settings-tab-automation")
      refute has_element?(view, "#settings-tab-workspace")
      refute has_element?(view, "#settings-panel-workspace")
      refute has_element?(view, "#settings-tab-security")
      refute has_element?(view, "#settings-panel-security")
      assert has_element?(view, "button#connect-microsoft-365[disabled]")
      assert has_element?(view, "#microsoft-365-availability")
      refute has_element?(view, "#settings-tab-notifications")
      refute has_element?(view, "#settings-panel-notifications")
      refute has_element?(view, "#topbar-notifications-button")
      refute has_element?(view, "#settings-tab-support")
      refute has_element?(view, "#sidebar-support-link")
    end

    test "opens Automation settings from its URL and updates review cleanup", %{
      conn: conn,
      org: org
    } do
      {:ok, view, _html} = conn |> org_conn(org) |> live("/settings?tab=automation")

      assert has_element?(view, "#settings-tab-automation.active")
      assert has_element?(view, "#settings-panel-automation:not(.hidden)")
      assert has_element?(view, "#settings-automation-review-cleanup-form")

      view
      |> form("#settings-automation-review-cleanup-form", %{
        "approval_expiry" => %{"approval_expiry_days" => "1"}
      })
      |> render_submit()

      assert Accounts.get_organization!(org.id).approval_expiry_days == 1
    end

    test "does not allow a zero-day review cleanup setting", %{conn: conn, org: org} do
      {:ok, view, _html} = conn |> org_conn(org) |> live("/settings?tab=automation")

      view
      |> form("#settings-automation-review-cleanup-form", %{
        "approval_expiry" => %{"approval_expiry_days" => "0"}
      })
      |> render_submit()

      assert Accounts.get_organization!(org.id).approval_expiry_days == 7
    end

    test "renders Gmail history import in mail settings", %{conn: conn, org: org, scope: scope} do
      conn = %{conn | host: "#{org.slug}.localhost"}

      integration =
        integration_fixture(scope, %{provider: :gmail, email_address: "me@example.com"})

      {:ok, view, _html} = live(conn, ~p"/settings")

      refute has_element?(view, "#settings-panel-general #gmail-backfill-form")

      open_mail(view)

      assert has_element?(view, "#settings-panel-mail:not(.hidden)")
      assert has_element?(view, "#settings-panel-mail #gmail-backfill-form")
      assert has_element?(view, "#settings-panel-mail #gmail-backfill-submit")
      assert render(view) =~ "Between dates"
      refute render(view) =~ ">Range<"
      refute has_element?(view, "#gmail-import-accounts")
      assert has_element?(view, "#mail-signature-import-#{integration.id}")
      assert has_element?(view, "#mail-import-gmail-signature-#{integration.id}")
      refute has_element?(view, "#mail-branding-signature-html-#{integration.id}-wrapper")
      refute has_element?(view, "#mail-branding-footer-html-#{integration.id}-wrapper")
      refute render(view) =~ "Forwarding"
      refute render(view) =~ "Templates"
    end

    test "replaces the Gmail signature import action after import and allows removal", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      integration =
        integration_fixture(scope, %{
          provider: :gmail,
          email_address: "signature@example.com",
          signature_html: "<p>Regards</p>"
        })

      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/settings")
      open_mail(view)

      assert has_element?(
               view,
               "#mail-import-gmail-signature-#{integration.id}",
               "Re-import Gmail signature"
             )

      assert has_element?(view, "#mail-remove-gmail-signature-#{integration.id}")

      view
      |> element("#mail-remove-gmail-signature-#{integration.id}")
      |> render_click()

      assert Inbox.get_integration!(scope, integration.id).signature_html == nil

      assert has_element?(
               view,
               "#mail-import-gmail-signature-#{integration.id}",
               "Import Gmail signature"
             )

      refute has_element?(view, "#mail-remove-gmail-signature-#{integration.id}")
    end

    test "shows a configuration warning when Gmail is not connected", %{conn: conn, org: org} do
      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/settings?tab=mail")

      assert has_element?(view, "#mail-configuration-required")
      assert has_element?(view, "#mail-configure-gmail-btn")
      assert has_element?(view, "#gmail-integration-status", "Not connected")
      assert has_element?(view, "#connect-gmail-btn.btn-primary")
      refute has_element?(view, "#gmail-backfill-empty")
      refute render(view) =~ "Import historical messages and tune mailbox defaults."
    end

    test "shows reconnect when the Gmail integration is disabled", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      integration_fixture(scope, %{
        provider: :gmail,
        email_address: "reauthorize@example.com",
        sync_enabled: false
      })

      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/settings")

      assert has_element?(view, "#reconnect-gmail-btn")
      assert has_element?(view, "#gmail-integration-status", "Reconnect needed")
      refute has_element?(view, "[id^=disconnect-gmail-]")
    end

    test "shows Gmail permission update action for a connected account", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      integration =
        integration_fixture(scope, %{provider: :gmail, email_address: "permissions@example.com"})

      {:ok, view, _html} = live(conn |> org_conn(org), ~p"/settings")

      assert has_element?(view, "#reconnect-gmail-btn")
      assert has_element?(view, "#disconnect-gmail-#{integration.id}")
      assert has_element?(view, "#gmail-integration-status", "Connected")
    end

    test "switches tabs", %{conn: conn, org: org} do
      conn = %{conn | host: "#{org.slug}.localhost"}

      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("#settings-tab-profile")
      |> render_click()

      assert has_element?(view, "#settings-panel-profile:not(.hidden)")
      assert has_element?(view, "#settings-panel-general.hidden")
    end

    test "switches tabs from the mobile picker", %{conn: conn, org: org} do
      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/settings")

      view
      |> render_hook("switch_tab", %{"settings_tab" => %{"tab" => "mail"}})

      assert_patch(view, ~p"/settings?tab=mail")
      assert has_element?(view, "#settings-panel-mail:not(.hidden)")
    end

    test "renders two-factor setup in Profile settings", %{conn: conn, org: org} do
      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/settings")

      view
      |> element("#settings-tab-profile")
      |> render_click()

      assert has_element?(view, "#settings-two-factor")
      assert has_element?(view, "#settings-two-factor-qr")
      assert has_element?(view, "#settings-enable-two-factor-form")
      assert has_element?(view, "#settings-enable-two-factor-submit")
    end

    test "opens a settings tab from its URL", %{conn: conn, org: org} do
      {:ok, view, _html} = conn |> org_conn(org) |> live("/settings?tab=mail")

      assert has_element?(view, "#settings-panel-mail:not(.hidden)")
      assert has_element?(view, "#settings-panel-general.hidden")
    end

    test "renders theme selection in appearance settings", %{conn: conn, org: org} do
      conn = %{conn | host: "#{org.slug}.localhost"}

      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("#settings-tab-appearance")
      |> render_click()

      assert has_element?(view, "#settings-panel-appearance:not(.hidden)")

      assert has_element?(view, "#settings-theme-corporate")
      assert has_element?(view, "#settings-theme-vscode")
      refute has_element?(view, "#settings-theme-claude")
    end

    test "renders AI response preferences", %{conn: conn, org: org} do
      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/settings")

      open_ai(view)

      assert has_element?(view, "#settings-panel-ai:not(.hidden)")
      assert has_element?(view, "#settings-ai-preferences-form")
      assert has_element?(view, "#settings-ai-preferences-submit")
      assert has_element?(view, "#settings-ai-tone-select input.h-10.cursor-pointer")
      assert has_element?(view, "#settings-ai-language-select input.h-10.cursor-pointer")
      assert has_element?(view, "#settings-ai-response-length-select input.h-10.cursor-pointer")
    end

    test "hides the profile identity form while keeping account settings", %{conn: conn, org: org} do
      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/settings")

      open_profile(view)

      refute has_element?(view, "#settings-profile-form")
      refute has_element?(view, "#settings-email-form")
      assert has_element?(view, "#settings-account-email")
      assert has_element?(view, "#settings-password-form")
      assert has_element?(view, "#settings-panel-profile:not(.hidden)")
    end
  end

  describe "Gmail history import" do
    setup :register_and_log_in_user_with_org

    test "queues a Gmail backfill job for the selected account", %{
      conn: conn,
      org: org,
      scope: scope
    } do
      conn = org_conn(conn, org)

      integration_fixture(scope, %{provider: :gmail, email_address: "first@example.com"})

      selected_integration =
        integration_fixture(scope, %{provider: :gmail, email_address: "selected@example.com"})

      {:ok, view, _html} = live(conn, ~p"/settings")

      open_mail(view)

      result =
        view
        |> form("#gmail-backfill-form", %{
          "backfill" => %{
            "integration_id" => to_string(selected_integration.id),
            "start_date" => "2026-01-01",
            "end_date" => "2026-01-31"
          }
        })
        |> render_submit()

      assert result =~ "Gmail history import queued"
      assert has_element?(view, "#gmail-backfill-status")

      assert Repo.get_by(Oban.Job,
               worker: "Konevo.Workers.GmailBackfillWorker",
               args: %{
                 "integration_id" => selected_integration.id,
                 "organization_id" => org.id,
                 "requested_by_id" => scope.user.id,
                 "query" => "after:2026/01/01 before:2026/02/01 -in:trash -in:spam"
               }
             )
    end
  end

  describe "update password form" do
    setup :register_and_log_in_user_with_org

    test "updates the user password", %{conn: conn, org: org, user: user} do
      new_password = valid_user_password()
      conn = org_conn(conn, org)
      {:ok, view, _html} = live(conn, ~p"/settings")

      open_profile(view)

      form =
        form(view, "#settings-password-form", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/settings"
      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :success) =~
               "Password updated"

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "renders errors with invalid data", %{conn: conn, org: org} do
      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/settings")

      open_profile(view)

      result =
        view
        |> form("#settings-password-form", %{
          "user" => %{
            "password" => "Ab1",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "should be at least 6 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "AI response preferences" do
    setup :register_and_log_in_user_with_org

    test "persists the current user's response preferences", %{conn: conn, org: org, scope: scope} do
      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/settings")

      open_ai(view)

      result =
        view
        |> form("#settings-ai-preferences-form", %{
          "preference" => %{
            "workspace_context" => "This inbox is for Company XYZ business inquiries.",
            "email_instructions" => "Keep replies short and ask one clear question.",
            "task_instructions" => "Create only explicit, unfinished tasks."
          }
        })
        |> render_submit()

      assert result =~ "AI response preferences updated"
      assert {:ok, preference} = AI.get_preference(scope)
      assert preference.tone == "professional"
      assert preference.language == "auto"
      assert preference.workspace_context == "This inbox is for Company XYZ business inquiries."
      assert preference.email_instructions == "Keep replies short and ask one clear question."
      assert preference.task_instructions == "Create only explicit, unfinished tasks."
    end

    test "persists provider keys", %{conn: conn, org: org, scope: scope} do
      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/settings")

      open_ai(view)

      result =
        view
        |> form("#settings-ai-provider-openai_responses-form", %{
          "provider_setting" => %{
            "provider" => "openai_responses",
            "api_key" => "sk-test-1234567890"
          }
        })
        |> render_submit()

      assert result =~ "AI provider settings saved"

      setting = AI.get_provider_setting(scope, :openai_responses)
      assert setting.api_key_last4 == "7890"
      assert {:ok, "sk-test-1234567890"} = AI.fetch_provider_api_key(scope, :openai_responses)
      assert has_element?(view, "#settings-ai-provider-openai_responses-key-hint", "sk-*****")

      refute has_element?(
               view,
               "#settings-ai-provider-openai_responses-key-hint",
               "sk-test-1234567890"
             )
    end

    test "renders provider usage without visible budget controls", %{conn: conn, org: org} do
      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/settings")

      open_ai(view)

      assert has_element?(view, "#settings-ai-language-select input.h-10.cursor-pointer")
      assert has_element?(view, "#settings-ai-general-heading")
      assert has_element?(view, "#settings-ai-email-heading")
      assert has_element?(view, "#settings-ai-task-heading")
      assert has_element?(view, "#settings-ai-provider-openai_responses-form")
      assert has_element?(view, "#settings-ai-usage-openai_responses")
      assert has_element?(view, "#settings-ai-model-usage")
      assert has_element?(view, "input[type='hidden']#settings-ai-budget-openai_responses")
      refute render(view) =~ "Monthly budget"
    end

    test "formats token usage compactly with exact totals on hover", %{
      conn: conn,
      org: org,
      user: user
    } do
      insert(:ai_run,
        organization: org,
        user: user,
        provider: "openai_responses",
        model_used: "gpt-5.6-terra",
        input_tokens: 10_581,
        output_tokens: 0
      )

      insert(:ai_run,
        organization: org,
        user: user,
        provider: "openai_responses",
        model_used: "gpt-5.6-luna",
        input_tokens: 1_500_000,
        output_tokens: 0
      )

      {:ok, view, _html} = conn |> org_conn(org) |> live(~p"/settings")

      open_ai(view)

      assert has_element?(view, "#settings-ai-model-usage [title='10,581 tokens']", "10K")

      assert has_element?(
               view,
               "#settings-ai-model-usage [title='1,510,581 tokens']",
               "1.5M"
             )
    end
  end

  defp open_profile(view) do
    view
    |> element("#settings-tab-profile")
    |> render_click()
  end

  defp open_mail(view) do
    view
    |> element("#settings-tab-mail")
    |> render_click()
  end

  defp open_ai(view) do
    view
    |> element("#settings-tab-ai")
    |> render_click()
  end

  defp org_conn(conn, org), do: %{conn | host: "#{org.slug}.localhost"}
end
