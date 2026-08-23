defmodule KonevoWeb.SettingsLive do
  use KonevoWeb, :live_view

  alias Konevo.Accounts
  alias Konevo.Accounts.Organization
  alias Konevo.AI
  alias Konevo.AI.{Preference, ProviderSetting}
  alias Konevo.Automation
  alias Konevo.Inbox

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    two_factor_setup_secret =
      if Accounts.two_factor_enabled?(user), do: nil, else: Accounts.new_two_factor_secret()

    integrations =
      if connected?(socket) do
        Konevo.Inbox.list_integrations(socket.assigns.current_scope)
      else
        nil
      end

    {:ok,
     socket
     |> assign(:page_title, gettext("Settings"))
     |> assign(:active_tab, "general")
     |> assign(:current_email, user.email)
     |> assign(:integrations, integrations)
     |> assign(:gmail_signature_importing_id, nil)
     |> assign(
       :ai_preference_form,
       ai_preference_form(socket.assigns.current_scope, connected?(socket))
     )
     |> assign(
       :ai_provider_forms,
       ai_provider_forms(socket.assigns.current_scope, connected?(socket))
     )
     |> assign(
       :ai_provider_usage,
       ai_provider_usage(socket.assigns.current_scope, connected?(socket))
     )
     |> assign(
       :ai_model_usage,
       ai_model_usage(socket.assigns.current_scope, connected?(socket))
     )
     |> assign(:profile_form, to_form(profile_params(user), as: "profile"))
     |> assign(:approval_expiry_form, approval_expiry_form(socket.assigns.current_scope))
     |> assign(:gmail_backfill_form, to_form(gmail_backfill_params(integrations), as: "backfill"))
     |> assign(:password_form, to_form(password_changeset))
     |> assign(:two_factor_enabled?, Accounts.two_factor_enabled?(user))
     |> assign(:two_factor_form, to_form(%{"code" => ""}, as: "two_factor"))
     |> assign(:two_factor_setup_secret, two_factor_setup_secret)
     |> assign(:two_factor_qr_code, two_factor_qr_code(user, two_factor_setup_secret))
     |> assign(:trigger_submit, false)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, assign(socket, :active_tab, settings_tab(Map.get(params, "tab")))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.page title={@page_title}>
        <div class="space-y-6">
          <div class="rounded-xl border-2 border-base-content/15 bg-base-100 shadow-md shadow-base-content/5">
            <div class="px-4 pt-3 sm:px-5">
              <%!-- Mobile tab select (visible only on small screens) --%>
              <select
                id="settings-tab-mobile-select"
                phx-hook=".SettingsTabSelect"
                phx-update="ignore"
                class="select select-bordered select-sm w-full mb-3 sm:hidden"
                aria-label={gettext("Settings tab")}
              >
                <option :for={tab <- tabs()} value={tab.id} selected={@active_tab == tab.id}>
                  {tab.label}
                </option>
              </select>
              <script :type={Phoenix.LiveView.ColocatedHook} name=".SettingsTabSelect">
                export default {
                  mounted() {
                    this.el.addEventListener('change', (e) => {
                      const tabId = e.target.value
                      this.pushEvent('switch_tab', {tab: tabId})
                    })
                  }
                }
              </script>
              <%!-- Desktop tab strip (hidden on small screens) --%>
              <nav
                id="settings-tabs"
                class="tabs tabs-bordered overflow-x-auto hidden sm:flex"
                aria-label={gettext("Settings tabs")}
                role="tablist"
                aria-orientation="horizontal"
              >
                <button
                  :for={tab <- tabs()}
                  type="button"
                  id={"settings-tab-#{tab.id}"}
                  class={[
                    "tab active-tab:tab-active active-tab:border-primary active-tab:text-primary gap-2 whitespace-nowrap rounded-none!",
                    @active_tab == tab.id &&
                      "active tab-active"
                  ]}
                  data-tab={tab.id}
                  data-settings-tab
                  phx-click="switch_tab"
                  phx-value-tab={tab.id}
                  aria-controls={"settings-panel-#{tab.id}"}
                  role="tab"
                  aria-selected={@active_tab == tab.id}
                >
                  <.icon name={tab.icon} class="size-4.5 shrink-0" />
                  {tab.label}
                </button>
              </nav>
            </div>

            <div class="p-4 sm:p-6">
              <div
                id="settings-panel-general"
                data-settings-panel
                class={@active_tab != "general" && "hidden"}
              >
                <.general_panel
                  integrations={@integrations}
                  current_scope={@current_scope}
                />
              </div>
              <div
                id="settings-panel-appearance"
                data-settings-panel
                class={@active_tab != "appearance" && "hidden"}
              >
                <.appearance_panel current_scope={@current_scope} />
              </div>
              <div
                id="settings-panel-profile"
                data-settings-panel
                class={@active_tab != "profile" && "hidden"}
              >
                <.profile_panel
                  form={@profile_form}
                  password_form={@password_form}
                  current_email={@current_email}
                  trigger_submit={@trigger_submit}
                  two_factor_enabled?={@two_factor_enabled?}
                  two_factor_form={@two_factor_form}
                  two_factor_qr_code={@two_factor_qr_code}
                />
              </div>
              <div
                id="settings-panel-mail"
                data-settings-panel
                class={@active_tab != "mail" && "hidden"}
              >
                <.mail_panel
                  integrations={@integrations}
                  backfill_form={@gmail_backfill_form}
                  gmail_signature_importing_id={@gmail_signature_importing_id}
                />
              </div>
              <div
                id="settings-panel-ai"
                data-settings-panel
                class={@active_tab != "ai" && "hidden"}
              >
                <.ai_panel
                  form={@ai_preference_form}
                  provider_forms={@ai_provider_forms}
                  provider_usage={@ai_provider_usage}
                  model_usage={@ai_model_usage}
                />
              </div>
              <div
                id="settings-panel-automation"
                data-settings-panel
                class={@active_tab != "automation" && "hidden"}
              >
                <.automation_panel form={@approval_expiry_form} />
              </div>
            </div>
          </div>
        </div>
      </Layouts.page>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    if Enum.any?(tabs(), &(&1.id == tab)) do
      {:noreply, push_patch(socket, to: ~p"/settings?tab=#{tab}")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_approval_expiry", %{"approval_expiry" => params}, socket) do
    case Automation.update_approval_expiry(socket.assigns.current_scope, params) do
      {:ok, organization} ->
        {:noreply,
         socket
         |> assign(:approval_expiry_form, approval_expiry_form_for(organization))
         |> put_flash(:success, gettext("Automation setting saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :approval_expiry_form, to_form(changeset, as: :approval_expiry))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot update automation settings"))}
    end
  end

  def handle_event("update_ai_preferences", %{"preference" => params}, socket) do
    scope = socket.assigns.current_scope

    case AI.update_preference(scope, params) do
      {:ok, preference} ->
        {:noreply,
         socket
         |> assign(:ai_preference_form, preference_form(preference))
         |> put_flash(:success, gettext("AI response preferences updated"))}

      {:error, changeset} ->
        {:noreply, assign(socket, :ai_preference_form, to_form(changeset))}
    end
  end

  def handle_event("update_ai_provider_settings", %{"provider_setting" => params}, socket) do
    scope = socket.assigns.current_scope

    case AI.update_provider_setting(scope, params) do
      {:ok, _setting} ->
        {:noreply,
         socket
         |> reload_ai_provider_settings()
         |> put_flash(:success, gettext("AI provider settings saved"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        provider = provider_form_key(Ecto.Changeset.get_field(changeset, :provider))

        {:noreply,
         assign(
           socket,
           :ai_provider_forms,
           Map.put(socket.assigns.ai_provider_forms, provider, provider_setting_form(changeset))
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save AI provider settings"))}
    end
  end

  def handle_event("update_view_prefs", %{"section" => section, "mode" => mode}, socket) do
    user = socket.assigns.current_scope.user

    attrs =
      case section do
        "contacts" -> %{contacts_view_mode: mode}
        "companies" -> %{companies_view_mode: mode}
        _ -> %{}
      end

    case Accounts.update_user_view_preferences(user, attrs) do
      {:ok, updated_user} ->
        updated_scope = %{socket.assigns.current_scope | user: updated_user}

        {:noreply,
         socket
         |> assign(:current_scope, updated_scope)
         |> put_flash(:success, gettext("Display preference updated"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update preference"))}
    end
  end

  def handle_event("disconnect_integration", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    id = String.to_integer(id)

    case Inbox.get_integration!(scope, id) do
      integration ->
        case Inbox.delete_integration(scope, integration) do
          {:ok, _} ->
            integrations = Inbox.list_integrations(scope)

            {:noreply,
             socket
             |> assign(:integrations, integrations)
             |> put_flash(:success, gettext("Email account disconnected"))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not disconnect account"))}
        end
    end
  rescue
    Ecto.NoResultsError ->
      {:noreply, put_flash(socket, :error, gettext("Integration not found"))}
  end

  def handle_event("validate_gmail_backfill", %{"backfill" => params}, socket) do
    {:noreply, assign(socket, :gmail_backfill_form, to_form(params, as: "backfill"))}
  end

  def handle_event("fetch_gmail_signature", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    integration = Inbox.get_integration!(scope, String.to_integer(id))

    {:noreply,
     socket
     |> assign(:gmail_signature_importing_id, integration.id)
     |> start_async({:gmail_signature_import, integration.id}, fn ->
       Inbox.import_gmail_primary_signature(scope, integration)
     end)}
  rescue
    Ecto.NoResultsError ->
      {:noreply, put_flash(socket, :error, gettext("Integration not found"))}
  end

  def handle_event("enqueue_gmail_backfill", %{"backfill" => params}, socket) do
    scope = socket.assigns.current_scope
    params = Map.put(params, "mode", "between")

    with {:ok, integration} <-
           selected_gmail_integration(socket.assigns.integrations, params["integration_id"]),
         {:ok, _job} <- Inbox.enqueue_gmail_backfill(scope, integration, params) do
      integration = Inbox.get_integration!(scope, integration.id)

      {:noreply,
       socket
       |> assign(:integrations, replace_integration(socket.assigns.integrations, integration))
       |> assign(:gmail_backfill_form, to_form(params, as: "backfill"))
       |> schedule_backfill_status_refresh()
       |> put_flash(:success, gettext("Gmail history import queued"))}
    else
      {:error, :no_gmail_integration} ->
        {:noreply, put_flash(socket, :error, gettext("Connect Gmail before importing history"))}

      {:error, :gmail_reauthorization_required} ->
        {:noreply, put_flash(socket, :error, gettext("Reconnect Gmail before importing history"))}

      {:error, :invalid_backfill_range} ->
        {:noreply, put_flash(socket, :error, gettext("Choose a valid import date range"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not queue Gmail history import"))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params

    if Accounts.sudo_mode?(socket.assigns.current_scope.user) do
      update_password(socket, user_params)
    else
      {:noreply, require_recent_login(socket)}
    end
  end

  def handle_event("enable_two_factor", %{"two_factor" => %{"code" => code}}, socket) do
    user = socket.assigns.current_scope.user

    with true <- Accounts.sudo_mode?(user),
         secret when is_binary(secret) <- socket.assigns.two_factor_setup_secret,
         {:ok, updated_user} <- Accounts.enable_two_factor(user, secret, code) do
      updated_scope = %{socket.assigns.current_scope | user: updated_user}

      {:noreply,
       socket
       |> assign(:current_scope, updated_scope)
       |> assign(:two_factor_enabled?, true)
       |> assign(:two_factor_setup_secret, nil)
       |> assign(:two_factor_qr_code, nil)
       |> assign(:two_factor_form, to_form(%{"code" => ""}, as: "two_factor"))
       |> put_flash(:success, gettext("Two-factor authentication is enabled"))}
    else
      false ->
        {:noreply, require_recent_login(socket)}

      {:error, :invalid_code} ->
        {:noreply, put_flash(socket, :error, gettext("Invalid verification code"))}

      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("Could not enable two-factor authentication"))}
    end
  end

  def handle_event("disable_two_factor", _params, socket) do
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      case Accounts.disable_two_factor(user) do
        {:ok, updated_user} ->
          updated_scope = %{socket.assigns.current_scope | user: updated_user}
          secret = Accounts.new_two_factor_secret()

          {:noreply,
           socket
           |> assign(:current_scope, updated_scope)
           |> assign(:two_factor_enabled?, false)
           |> assign(:two_factor_setup_secret, secret)
           |> assign(:two_factor_qr_code, two_factor_qr_code(updated_user, secret))
           |> put_flash(:success, gettext("Two-factor authentication is disabled"))}

        {:error, _changeset} ->
          {:noreply,
           put_flash(socket, :error, gettext("Could not disable two-factor authentication"))}
      end
    else
      {:noreply, require_recent_login(socket)}
    end
  end

  @impl true
  def handle_info(:refresh_gmail_backfill_status, socket) do
    integrations = Inbox.list_integrations(socket.assigns.current_scope)

    socket = assign(socket, :integrations, integrations)

    {:noreply,
     if(backfill_in_progress?(integrations),
       do: schedule_backfill_status_refresh(socket),
       else: socket
     )}
  end

  @impl true
  def handle_async({:gmail_signature_import, _id}, {:ok, {:ok, updated}}, socket) do
    integrations = replace_integration(socket.assigns.integrations, updated)

    {:noreply,
     socket
     |> assign(:integrations, integrations)
     |> assign(:gmail_signature_importing_id, nil)
     |> put_flash(:success, gettext("Gmail signature imported"))}
  end

  def handle_async({:gmail_signature_import, _id}, {:ok, {:error, _reason}}, socket) do
    {:noreply,
     socket
     |> assign(:gmail_signature_importing_id, nil)
     |> put_flash(:error, gettext("Could not import Gmail signature"))}
  end

  def handle_async({:gmail_signature_import, _id}, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:gmail_signature_importing_id, nil)
     |> put_flash(:error, gettext("Could not import Gmail signature"))}
  end

  defp update_password(socket, user_params) do
    user = socket.assigns.current_scope.user

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  defp require_recent_login(socket) do
    socket
    |> put_flash(:error, gettext("You must re-authenticate to access this page"))
    |> push_navigate(to: ~p"/users/log-in")
  end

  defp two_factor_qr_code(_user, nil), do: nil

  defp two_factor_qr_code(user, secret) do
    user
    |> Accounts.two_factor_otpauth_uri(secret)
    |> EQRCode.encode()
    |> EQRCode.svg(color: "#111827", background_color: "#FFFFFF", width: 160)
    |> Base.encode64()
    |> then(&"data:image/svg+xml;base64,#{&1}")
  end

  defp ai_preference_form(scope, true) do
    case AI.get_preference(scope) do
      {:ok, preference} -> preference_form(preference)
      {:error, _reason} -> preference_form(%Preference{})
    end
  end

  defp ai_preference_form(_scope, false), do: preference_form(%Preference{})
  defp preference_form(preference), do: preference |> Preference.changeset(%{}) |> to_form()

  defp ai_provider_forms(scope, true) do
    scope
    |> AI.list_provider_settings()
    |> Map.new(fn setting ->
      {provider_form_key(setting.provider), provider_setting_form(setting)}
    end)
  end

  defp ai_provider_forms(_scope, false) do
    ProviderSetting.providers()
    |> Map.new(fn provider ->
      {provider_form_key(provider), provider_setting_form(%ProviderSetting{provider: provider})}
    end)
  end

  defp provider_setting_form(%Ecto.Changeset{} = changeset) do
    changeset
    |> redact_provider_api_key()
    |> to_form(as: "provider_setting")
  end

  defp provider_setting_form(%ProviderSetting{} = setting) do
    setting
    |> ProviderSetting.changeset(%{})
    |> to_form(as: "provider_setting")
  end

  defp redact_provider_api_key(changeset) do
    params =
      changeset.params
      |> Kernel.||(%{})
      |> Map.put("api_key", "")

    %{changeset | params: params, changes: Map.delete(changeset.changes, :api_key)}
  end

  defp ai_provider_usage(scope, true), do: AI.provider_usage_summary(scope)

  defp ai_provider_usage(_scope, false) do
    Enum.map(ProviderSetting.providers(), fn provider ->
      %{
        provider: provider,
        provider_value: provider_form_key(provider),
        api_key_last4: nil,
        api_key_mask: nil,
        has_api_key?: false,
        monthly_budget: nil,
        input_tokens: 0,
        output_tokens: 0,
        total_tokens: 0,
        runs: 0,
        estimated_spend: Decimal.new("0.00"),
        period_start:
          DateTime.new!(Date.beginning_of_month(Date.utc_today()), ~T[00:00:00], "Etc/UTC")
      }
    end)
  end

  defp ai_model_usage(scope, true), do: AI.model_usage_summary(scope)

  defp ai_model_usage(_scope, false) do
    period_start =
      DateTime.new!(Date.beginning_of_month(Date.utc_today()), ~T[00:00:00], "Etc/UTC")

    Enum.map(
      [
        {:terra, "GPT-5.6 Terra", "gpt-5.6-terra"},
        {:luna, "GPT-5.6 Luna", "gpt-5.6-luna"}
      ],
      fn {id, label, model} ->
        %{
          id: id,
          label: label,
          model: model,
          input_tokens: 0,
          output_tokens: 0,
          total_tokens: 0,
          runs: 0,
          estimated_spend: Decimal.new("0.00"),
          period_start: period_start
        }
      end
    )
  end

  defp reload_ai_provider_settings(socket) do
    socket
    |> assign(:ai_provider_forms, ai_provider_forms(socket.assigns.current_scope, true))
    |> assign(:ai_provider_usage, ai_provider_usage(socket.assigns.current_scope, true))
    |> assign(:ai_model_usage, ai_model_usage(socket.assigns.current_scope, true))
  end

  defp provider_form_key(provider) when provider == :openai_responses,
    do: Atom.to_string(provider)

  defp provider_form_key(provider) when is_binary(provider), do: provider
  defp provider_form_key(_provider), do: "openai_responses"

  defp tabs do
    [
      %{id: "general", label: gettext("General"), icon: "icon-[tabler--settings]"},
      %{id: "appearance", label: gettext("Appearance"), icon: "icon-[tabler--palette]"},
      %{id: "profile", label: gettext("Profile"), icon: "icon-[tabler--user-circle]"},
      %{id: "mail", label: gettext("Mail"), icon: "icon-[tabler--mail]"},
      %{id: "ai", label: gettext("AI"), icon: "icon-[tabler--sparkles]"},
      %{id: "automation", label: gettext("Automation"), icon: "icon-[tabler--bolt]"}
    ]
  end

  defp settings_tab(tab) do
    if Enum.any?(tabs(), &(&1.id == tab)), do: tab, else: "general"
  end

  defp approval_expiry_form(scope) do
    scope
    |> Automation.change_approval_expiry()
    |> to_form(as: :approval_expiry)
  end

  defp approval_expiry_form_for(organization) do
    organization
    |> Organization.approval_expiry_changeset(%{})
    |> to_form(as: :approval_expiry)
  end

  defp theme_options do
    [
      %{
        id: "corporate",
        label: gettext("Light"),
        description: gettext("Corporate Blue"),
        icon: "icon-[tabler--sun]",
        preview: "bg-blue-50 text-blue-950 border-blue-200"
      },
      %{
        id: "vscode",
        label: gettext("Dark"),
        description: gettext("VS Code"),
        icon: "icon-[tabler--moon]",
        preview: "bg-slate-900 text-sky-100 border-slate-700"
      }
    ]
  end

  defp profile_params(user) do
    %{
      "email" => user.email,
      "name" => "",
      "title" => "",
      "phone" => ""
    }
  end

  defp gmail_backfill_params(integrations) do
    today = Date.utc_today()

    %{
      "integration_id" => default_gmail_integration_id(integrations),
      "mode" => "since",
      "start_date" => today |> Date.add(-365) |> Date.to_iso8601(),
      "end_date" => Date.to_iso8601(today)
    }
  end

  defp default_gmail_integration_id(nil), do: ""

  defp default_gmail_integration_id(integrations) do
    case List.first(gmail_integrations(integrations)) do
      nil -> ""
      integration -> to_string(integration.id)
    end
  end

  defp selected_gmail_integration(nil, _id), do: {:error, :no_gmail_integration}

  defp selected_gmail_integration(integrations, id) when id in [nil, ""] do
    active_gmail_integration(integrations)
  end

  defp selected_gmail_integration(integrations, id) do
    case Enum.find(gmail_integrations(integrations), &(to_string(&1.id) == id)) do
      nil -> {:error, :no_gmail_integration}
      %{sync_enabled: false} -> {:error, :gmail_reauthorization_required}
      integration -> {:ok, integration}
    end
  end

  defp active_gmail_integration(nil), do: {:error, :no_gmail_integration}

  defp active_gmail_integration(integrations) do
    case Enum.find(gmail_integrations(integrations), & &1.sync_enabled) do
      nil -> {:error, :no_gmail_integration}
      integration -> {:ok, integration}
    end
  end

  defp gmail_integrations(nil), do: []

  defp gmail_integrations(integrations) do
    Enum.filter(integrations, &(&1.provider == :gmail))
  end

  defp gmail_connected?(%{sync_enabled: true}), do: true
  defp gmail_connected?(_integration), do: false

  defp gmail_import_options(integrations) do
    Enum.map(integrations, &{&1.email_address, to_string(&1.id)})
  end

  defp schedule_backfill_status_refresh(socket) do
    Process.send_after(self(), :refresh_gmail_backfill_status, 1_500)
    socket
  end

  defp backfill_in_progress?(integrations) do
    Enum.any?(gmail_integrations(integrations), fn integration ->
      integration.history_import_status in ["queued", "running"]
    end)
  end

  defp backfill_integration(integrations, form) do
    integration_id = form[:integration_id].value

    Enum.find(integrations, &(to_string(&1.id) == integration_id)) || List.first(integrations)
  end

  defp gmail_backfill_status_class("queued"),
    do: "border-primary/20 bg-primary/5 text-primary"

  defp gmail_backfill_status_class("running"),
    do: "border-primary/20 bg-primary/5 text-primary"

  defp gmail_backfill_status_class("completed"),
    do: "border-primary/20 bg-primary/5 text-primary"

  defp gmail_backfill_status_class("failed"),
    do: "border-error/20 bg-error/5 text-error"

  defp gmail_backfill_status_class(_status),
    do: "border-base-content/10 bg-base-200/35 text-base-content/60"

  defp gmail_backfill_status_icon("queued"), do: "icon-[tabler--clock]"
  defp gmail_backfill_status_icon("running"), do: "icon-[tabler--loader-2]"
  defp gmail_backfill_status_icon("completed"), do: "icon-[tabler--circle-check]"
  defp gmail_backfill_status_icon("failed"), do: "icon-[tabler--alert-circle]"
  defp gmail_backfill_status_icon(_status), do: "icon-[tabler--info-circle]"

  defp gmail_backfill_status_title(%{history_import_status: "queued"}),
    do: gettext("Gmail history import queued")

  defp gmail_backfill_status_title(%{history_import_status: "running"}),
    do: gettext("Importing Gmail history")

  defp gmail_backfill_status_title(%{history_import_status: "completed"}),
    do: gettext("Gmail history import completed")

  defp gmail_backfill_status_title(%{history_import_status: "failed"}),
    do: gettext("Gmail history import failed")

  defp gmail_backfill_status_title(_integration), do: gettext("Gmail history import")

  defp gmail_backfill_status_detail(%{history_import_status: "queued"}),
    do: gettext("Waiting for a background worker to start the import.")

  defp gmail_backfill_status_detail(%{history_import_status: "running"}),
    do: gettext("Messages will appear in Inbox as they are imported.")

  defp gmail_backfill_status_detail(%{
         history_import_status: "completed",
         history_imported_threads: imported,
         history_processed_threads: processed
       }) do
    refreshed = max(processed - imported, 0)

    ngettext("Added %{count} new thread.", "Added %{count} new threads.", imported,
      count: imported
    ) <>
      " " <>
      ngettext(
        "Refreshed %{count} existing thread.",
        "Refreshed %{count} existing threads.",
        refreshed,
        count: refreshed
      )
  end

  defp gmail_backfill_status_detail(%{history_import_status: "failed"}),
    do: gettext("The import did not complete. Try again or reconnect Gmail.")

  defp gmail_backfill_status_detail(_integration), do: ""

  defp replace_integration(nil, _updated), do: nil

  defp replace_integration(integrations, updated) do
    Enum.map(integrations, fn integration ->
      if integration.id == updated.id, do: updated, else: integration
    end)
  end

  attr(:title, :string, required: true)
  attr(:subtitle, :string, required: true)
  attr(:icon, :string, required: true)

  slot(:inner_block, required: true)

  defp settings_section(assigns) do
    ~H"""
    <section>
      <div class="mb-4">
        <h2 class="text-base font-semibold text-base-content">{@title}</h2>
        <p class="text-sm text-base-content/60">{@subtitle}</p>
      </div>
      <div class="min-w-0 space-y-4">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr(:integrations, :any, required: true)
  attr(:current_scope, :map, required: true)

  defp general_panel(assigns) do
    loading = is_nil(assigns.integrations)

    gmail_integration =
      if assigns.integrations,
        do: Enum.find(assigns.integrations, &(&1.provider == :gmail))

    assigns =
      assigns
      |> assign(:loading, loading)
      |> assign(:gmail_integration, gmail_integration)
      |> assign(
        :can_disconnect_gmail?,
        can_disconnect_gmail?(assigns.current_scope, gmail_integration)
      )

    ~H"""
    <div
      role="tabpanel"
      aria-labelledby="settings-tab-general"
      class="space-y-8"
    >
      <.settings_section
        title={gettext("General")}
        subtitle={gettext("Connect core tools for your workspace.")}
        icon="icon-[tabler--settings]"
      >
        <div class="grid gap-3 md:grid-cols-2">
          <%!-- Google Workspace card --%>
          <div class="overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm">
            <div class="border-b border-base-content/10 bg-base-200/35 p-4">
              <div class="flex items-start justify-between gap-3">
                <div class="flex items-center gap-3">
                  <div class="flex size-11 shrink-0 items-center justify-center rounded-lg border border-base-content/10 bg-base-100 shadow-sm">
                    <img src={~p"/icons/google_logo.svg"} alt="" class="size-6" />
                  </div>
                  <div>
                    <h3 class="text-base font-semibold leading-tight text-base-content">
                      {gettext("Google Workspace")}
                    </h3>
                    <p class="text-sm text-base-content/55">
                      <%= cond do %>
                        <% gmail_connected?(@gmail_integration) -> %>
                          <span class="inline-flex items-center gap-1.5">
                            <.icon
                              name="icon-[tabler--mail-check]"
                              class="size-3.5 shrink-0"
                              style={"color: #{primary_color()}"}
                            />
                            <span class="truncate">{@gmail_integration.email_address}</span>
                          </span>
                        <% @gmail_integration -> %>
                          <span class="inline-flex items-center gap-1.5 text-warning">
                            <.icon
                              name="icon-[tabler--alert-triangle]"
                              class="size-3.5 shrink-0"
                            />
                            <span class="truncate">{@gmail_integration.email_address}</span>
                          </span>
                        <% true -> %>
                          {gettext("Gmail and Calendar")}
                      <% end %>
                    </p>
                  </div>
                </div>
                <div :if={not @loading} class="flex items-center gap-2">
                  <span
                    :if={gmail_connected?(@gmail_integration)}
                    class="tooltip tooltip-left"
                    data-tip={gettext("Update Gmail permissions")}
                  >
                    <.link
                      href={~p"/integrations/gmail/consent"}
                      id="reconnect-gmail-btn"
                      class="btn btn-ghost btn-xs btn-square"
                      aria-label={gettext("Update Gmail permissions")}
                    >
                      <.icon name="icon-[tabler--refresh]" class="size-3.5" />
                    </.link>
                  </span>
                  <.integration_status_pill
                    connected={gmail_connected?(@gmail_integration)}
                    configured={not is_nil(@gmail_integration)}
                  />
                </div>
                <div
                  :if={@loading}
                  class="h-6 w-24 animate-pulse rounded-md bg-base-content/10"
                />
              </div>
            </div>
            <div class="space-y-4 p-4">
              <p class="text-sm leading-relaxed text-base-content/60">
                {gettext("Sync Gmail, calendar events, and sender identity.")}
              </p>
              <%= cond do %>
                <% @loading -> %>
                  <div class="h-8 animate-pulse rounded-lg bg-base-content/8" />
                <% gmail_connected?(@gmail_integration) -> %>
                  <div :if={@can_disconnect_gmail?} class="pt-1">
                    <button
                      type="button"
                      id={"disconnect-gmail-#{@gmail_integration.id}"}
                      class="btn btn-error btn-danger btn-sm w-full gap-1.5"
                      phx-click="disconnect_integration"
                      phx-value-id={@gmail_integration.id}
                      data-confirm={gettext("Disconnect Gmail? This will stop syncing emails.")}
                    >
                      <.icon name="icon-[tabler--plug-x]" class="size-3.5" />
                      {gettext("Disconnect Gmail")}
                    </button>
                  </div>
                <% @gmail_integration -> %>
                  <.link
                    href={~p"/integrations/gmail/consent"}
                    id="reconnect-gmail-btn"
                    class="btn btn-primary btn-sm w-full gap-1.5"
                  >
                    <.icon name="icon-[tabler--refresh]" class="size-4" />
                    {gettext("Reconnect Gmail")}
                  </.link>
                <% true -> %>
                  <.link
                    href={~p"/integrations/gmail/consent"}
                    id="connect-gmail-btn"
                    class="btn btn-sm w-full gap-1.5 bg-base-content text-base-100 hover:bg-base-content/85"
                  >
                    <.icon name="icon-[tabler--plug-connected]" class="size-4" />
                    {gettext("Connect Gmail")}
                  </.link>
              <% end %>
            </div>
          </div>

          <%!-- Microsoft 365 card --%>
          <div class="overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm">
            <div class="border-b border-base-content/10 bg-base-200/35 p-4">
              <div class="flex items-start justify-between gap-3">
                <div class="flex items-center gap-3">
                  <div class="flex size-11 shrink-0 items-center justify-center rounded-lg border border-base-content/10 bg-base-100 shadow-sm">
                    <img src={~p"/icons/microsoft_logo.svg"} alt="" class="size-6" />
                  </div>
                  <div>
                    <h3 class="text-base font-semibold leading-tight text-base-content">
                      {gettext("Microsoft 365")}
                    </h3>
                    <p class="text-sm text-base-content/55">{gettext("Outlook and Calendar")}</p>
                  </div>
                </div>
                <span
                  :if={not @loading}
                  id="microsoft-365-availability"
                  class="inline-flex shrink-0 items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-medium"
                  style={microsoft_availability_style()}
                >
                  <span class="size-1.5 rounded-full bg-current" />
                  {gettext("Not supported yet")}
                </span>
                <div
                  :if={@loading}
                  class="h-6 w-24 animate-pulse rounded-md bg-base-content/10"
                />
              </div>
            </div>
            <div class="space-y-4 p-4">
              <p class="text-sm leading-relaxed text-base-content/60">
                {gettext("Microsoft 365 is not available in the first release.")}
              </p>
              <%= if @loading do %>
                <div class="h-8 animate-pulse rounded-lg bg-base-content/8" />
              <% else %>
                <button
                  id="connect-microsoft-365"
                  type="button"
                  class="btn btn-sm w-full gap-1.5"
                  disabled
                >
                  <.icon name="icon-[tabler--clock-hour-4]" class="size-4" />
                  {gettext("Not Available")}
                </button>
              <% end %>
            </div>
          </div>
        </div>
      </.settings_section>
    </div>
    """
  end

  defp can_disconnect_gmail?(_scope, nil), do: false

  defp can_disconnect_gmail?(%{user: %{id: user_id}}, %{user_id: user_id}), do: true

  defp can_disconnect_gmail?(%{membership: %{role: role}}, _integration)
       when role in [:owner, :admin],
       do: true

  defp can_disconnect_gmail?(%{membership: %{custom_permissions: permissions}}, _integration),
    do: "inbox:delete" in permissions

  defp can_disconnect_gmail?(_scope, _integration), do: false

  attr(:connected, :boolean, required: true)
  attr(:configured, :boolean, required: true)

  defp integration_status_pill(assigns) do
    state =
      cond do
        assigns.connected -> :connected
        assigns.configured -> :reconnect_needed
        true -> :not_connected
      end

    assigns = assign(assigns, :state, state)

    ~H"""
    <span
      id="gmail-integration-status"
      class="inline-flex shrink-0 items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-medium"
      style={gmail_integration_status_style(@state)}
    >
      <span class="size-1.5 rounded-full bg-current" />
      {integration_status_label(@state)}
    </span>
    """
  end

  defp integration_status_label(:connected), do: gettext("Connected")
  defp integration_status_label(:reconnect_needed), do: gettext("Reconnect needed")
  defp integration_status_label(:not_connected), do: gettext("Not connected")

  defp primary_color, do: "var(--color-primary)"

  defp integration_status_style(true), do: gmail_integration_status_style(:connected)

  defp gmail_integration_status_style(:connected) do
    color = primary_color()

    [
      "background-color: color-mix(in srgb, #{color} 14%, transparent)",
      "border-color: color-mix(in srgb, #{color} 35%, transparent)",
      "color: #{color}"
    ]
    |> Enum.join("; ")
  end

  defp gmail_integration_status_style(:reconnect_needed) do
    color = "#f59e0b"

    [
      "background-color: color-mix(in srgb, #{color} 12%, transparent)",
      "border-color: color-mix(in srgb, #{color} 30%, transparent)",
      "color: color-mix(in srgb, #{color} 78%, var(--color-base-content))"
    ]
    |> Enum.join("; ")
  end

  defp gmail_integration_status_style(:not_connected) do
    color = "var(--color-base-content)"

    [
      "background-color: color-mix(in srgb, #{color} 6%, transparent)",
      "border-color: color-mix(in srgb, #{color} 12%, transparent)",
      "color: color-mix(in srgb, #{color} 55%, transparent)"
    ]
    |> Enum.join("; ")
  end

  defp microsoft_availability_style do
    color = "#0078d4"

    [
      "background-color: color-mix(in srgb, #{color} 12%, transparent)",
      "border-color: color-mix(in srgb, #{color} 30%, transparent)",
      "color: color-mix(in srgb, #{color} 78%, var(--color-base-content))"
    ]
    |> Enum.join("; ")
  end

  attr(:current_scope, :map, required: true)

  defp appearance_panel(assigns) do
    ~H"""
    <div
      role="tabpanel"
      aria-labelledby="settings-tab-appearance"
      class="space-y-8"
    >
      <.settings_section
        title={gettext("Appearance")}
        subtitle={gettext("Choose the color theme used across Konevo.")}
        icon="icon-[tabler--palette]"
      >
        <div
          id="appearance-theme-grid"
          phx-hook=".AppearanceThemePicker"
          class="grid gap-3 sm:grid-cols-2"
        >
          <button
            :for={theme <- theme_options()}
            type="button"
            id={"settings-theme-#{theme.id}"}
            class={[
              "flex items-center gap-3 rounded-xl border border-base-content/10 bg-base-200/40 p-4 text-left",
              "transition-colors hover:border-primary/30 hover:bg-primary/5"
            ]}
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme={theme.id}
          >
            <span class={[
              "flex size-9 shrink-0 items-center justify-center rounded-lg border shadow-sm",
              theme.preview
            ]}>
              <.icon name={theme.icon} class="size-4" />
            </span>
            <span class="min-w-0">
              <span class="block text-sm font-semibold text-base-content">{theme.label}</span>
              <span class="block text-xs text-base-content/55">{theme.description}</span>
            </span>
          </button>
        </div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".AppearanceThemePicker">
          export default {
            mounted() {
              this.updateActive()
              this._themeHandler = () => setTimeout(() => this.updateActive(), 0)
              window.addEventListener("phx:set-theme", this._themeHandler)
            },
            destroyed() {
              window.removeEventListener("phx:set-theme", this._themeHandler)
            },
            updateActive() {
              const stored = localStorage.getItem("phx:theme")
              const current = stored === "vscode" ? "vscode" : "corporate"
              this.el.querySelectorAll("[data-phx-theme]").forEach(btn => {
                const isActive = btn.dataset.phxTheme === current
                btn.classList.toggle("ring-2", isActive)
                btn.classList.toggle("ring-primary", isActive)
                btn.classList.toggle("border-primary/40", isActive)
                btn.classList.toggle("bg-primary/5", isActive)
                btn.classList.toggle("border-base-content/10", !isActive)
              })
            }
          }
        </script>
      </.settings_section>

      <%!-- Display preferences --%>
      <.settings_section
        title={gettext("Display")}
        subtitle={gettext("Choose how contacts and companies are displayed.")}
        icon="icon-[tabler--layout-grid]"
      >
        <div class="space-y-3">
          <%!-- Contacts view mode --%>
          <div class="flex items-center justify-between gap-4 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
            <div class="flex items-center gap-3">
              <div class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                <.icon name="icon-[tabler--users]" class="size-5" />
              </div>
              <div>
                <p class="text-sm font-semibold text-base-content">{gettext("Contacts")}</p>
                <p class="text-xs text-base-content/50">
                  {gettext("Default layout for the contacts page")}
                </p>
              </div>
            </div>
            <div class="flex items-center gap-1 rounded-lg border border-base-content/15 bg-base-100 p-1">
              <button
                type="button"
                phx-click="update_view_prefs"
                phx-value-section="contacts"
                phx-value-mode="table"
                class={[
                  "flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium transition-all",
                  if(@current_scope.user.contacts_view_mode == "table",
                    do: "bg-primary text-primary-content shadow-sm",
                    else: "text-base-content/60 hover:text-base-content"
                  )
                ]}
              >
                <.icon name="icon-[tabler--table]" class="size-3.5" />
                {gettext("Table")}
              </button>
              <button
                type="button"
                phx-click="update_view_prefs"
                phx-value-section="contacts"
                phx-value-mode="card"
                class={[
                  "flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium transition-all",
                  if(@current_scope.user.contacts_view_mode == "card",
                    do: "bg-primary text-primary-content shadow-sm",
                    else: "text-base-content/60 hover:text-base-content"
                  )
                ]}
              >
                <.icon name="icon-[tabler--layout-grid]" class="size-3.5" />
                {gettext("Cards")}
              </button>
            </div>
          </div>

          <%!-- Companies view mode --%>
          <div class="flex items-center justify-between gap-4 rounded-xl border border-base-content/10 bg-base-200/30 p-4">
            <div class="flex items-center gap-3">
              <div class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-secondary/10 text-secondary">
                <.icon name="icon-[tabler--building]" class="size-5" />
              </div>
              <div>
                <p class="text-sm font-semibold text-base-content">{gettext("Companies")}</p>
                <p class="text-xs text-base-content/50">
                  {gettext("Default layout for the companies page")}
                </p>
              </div>
            </div>
            <div class="flex items-center gap-1 rounded-lg border border-base-content/15 bg-base-100 p-1">
              <button
                type="button"
                phx-click="update_view_prefs"
                phx-value-section="companies"
                phx-value-mode="table"
                class={[
                  "flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium transition-all",
                  if(@current_scope.user.companies_view_mode == "table",
                    do: "bg-primary text-primary-content shadow-sm",
                    else: "text-base-content/60 hover:text-base-content"
                  )
                ]}
              >
                <.icon name="icon-[tabler--table]" class="size-3.5" />
                {gettext("Table")}
              </button>
              <button
                type="button"
                phx-click="update_view_prefs"
                phx-value-section="companies"
                phx-value-mode="card"
                class={[
                  "flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium transition-all",
                  if(@current_scope.user.companies_view_mode == "card",
                    do: "bg-primary text-primary-content shadow-sm",
                    else: "text-base-content/60 hover:text-base-content"
                  )
                ]}
              >
                <.icon name="icon-[tabler--layout-grid]" class="size-3.5" />
                {gettext("Cards")}
              </button>
            </div>
          </div>
        </div>
      </.settings_section>
    </div>
    """
  end

  attr(:form, :map, required: true)
  attr(:password_form, :map, required: true)
  attr(:current_email, :string, required: true)
  attr(:trigger_submit, :boolean, required: true)
  attr(:two_factor_enabled?, :boolean, required: true)
  attr(:two_factor_form, :map, required: true)
  attr(:two_factor_qr_code, :string, default: nil)

  defp profile_panel(assigns) do
    ~H"""
    <div
      role="tabpanel"
      aria-labelledby="settings-tab-profile"
      class="space-y-8"
    >
      <.settings_section
        title={gettext("Profile")}
        subtitle={gettext("Keep your identity and login preferences ready.")}
        icon="icon-[tabler--user-circle]"
      >
        <div class="grid gap-4 lg:grid-cols-2">
          <div class="rounded-xl border border-base-content/10 bg-base-100 p-4 shadow-sm">
            <div class="mb-4 flex items-start gap-3">
              <div class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                <.icon name="icon-[tabler--mail-cog]" class="size-5" />
              </div>
              <div>
                <h3 class="text-sm font-semibold text-base-content">{gettext("Account email")}</h3>
                <p class="text-sm text-base-content/60">
                  {gettext("Your sign-in email is managed by your workspace administrator.")}
                </p>
              </div>
            </div>
            <div
              id="settings-account-email"
              class="rounded-lg border border-base-content/10 bg-base-200/40 px-3 py-2.5"
            >
              <p class="text-xs font-medium uppercase tracking-wide text-base-content/50">
                {gettext("Account email")}
              </p>
              <p class="mt-1 truncate text-sm font-medium text-base-content">{@current_email}</p>
            </div>
          </div>

          <div class="rounded-xl border border-base-content/10 bg-base-100 p-4 shadow-sm">
            <div class="mb-4 flex items-start gap-3">
              <div class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                <.icon name="icon-[tabler--lock-password]" class="size-5" />
              </div>
              <div>
                <h3 class="text-sm font-semibold text-base-content">{gettext("Password")}</h3>
                <p class="text-sm text-base-content/60">
                  {gettext("Update your password and refresh active sessions.")}
                </p>
              </div>
            </div>
            <.form
              for={@password_form}
              id="settings-password-form"
              action={~p"/users/update-password"}
              method="post"
              phx-change="validate_password"
              phx-submit="update_password"
              phx-trigger-action={@trigger_submit}
              class="space-y-4"
            >
              <input
                name={@password_form[:email].name}
                type="hidden"
                id="settings-hidden-user-email"
                spellcheck="false"
                value={@current_email}
              />
              <.input
                field={@password_form[:password]}
                type="password"
                label={gettext("New password")}
                autocomplete="new-password"
                spellcheck="false"
                required
              />
              <.input
                field={@password_form[:password_confirmation]}
                type="password"
                label={gettext("Confirm new password")}
                autocomplete="new-password"
                spellcheck="false"
              />
              <button
                type="submit"
                class="btn btn-primary btn-sm mt-4"
                phx-disable-with={gettext("Saving...")}
              >
                <.icon name="icon-[tabler--device-floppy]" class="size-4" />
                {gettext("Save password")}
              </button>
            </.form>
          </div>
        </div>

        <div
          id="settings-two-factor"
          class="rounded-xl border border-base-content/10 bg-base-200/40 p-4"
        >
          <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div class="flex items-start gap-3">
              <div class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                <.icon name="icon-[tabler--lock-check]" class="size-5" />
              </div>
              <div>
                <p class="text-sm font-semibold text-base-content">
                  {gettext("Multi-factor authentication")}
                </p>
                <p class="text-sm text-base-content/60">
                  {gettext("Protect every sign-in with your authenticator app.")}
                </p>
              </div>
            </div>
            <div :if={@two_factor_enabled?} class="flex shrink-0 self-end sm:self-center">
              <div
                aria-hidden="true"
                class="hidden"
              >
                <span>•</span><span>•</span><span>•</span><span>•</span><span>•</span><span>•</span>
              </div>
              <button
                type="button"
                id="settings-disable-two-factor"
                class="btn btn-error btn-sm h-8 min-h-8 gap-1.5"
                phx-click="disable_two_factor"
                data-confirm={gettext("Disable two-factor authentication for this account?")}
              >
                <.icon name="icon-[tabler--shield-x]" class="size-4" />
                {gettext("Turn off")}
              </button>
            </div>
          </div>
          <%= if @two_factor_enabled? do %>
            <div class="mt-5 flex flex-wrap items-center gap-3 border-t border-base-content/10 pt-5">
              <span class="inline-flex items-center gap-1.5 rounded-full bg-primary/10 px-3 py-1.5 text-sm font-medium text-primary">
                <.icon name="icon-[tabler--shield-check]" class="size-4" />
                {gettext("Enabled")}
              </span>
              <p class="text-sm text-base-content/60">
                {gettext("Your account requires an authenticator code at sign-in.")}
              </p>
            </div>
          <% end %>
          <%= if not @two_factor_enabled? do %>
            <div class="mt-5 grid gap-5 border-t border-base-content/10 pt-5 sm:grid-cols-[12rem_minmax(0,1fr)] sm:items-center">
              <div class="mx-auto rounded-2xl border border-base-content/10 bg-white p-3 shadow-sm">
                <img
                  id="settings-two-factor-qr"
                  src={@two_factor_qr_code}
                  alt={gettext("Authenticator setup QR code")}
                  class="size-40"
                />
              </div>
              <div>
                <h3 class="text-sm font-semibold text-base-content">
                  {gettext("Set up your authenticator")}
                </h3>
                <p class="mt-1 text-sm leading-6 text-base-content/60">
                  {gettext(
                    "Scan the QR code with Google Authenticator, 1Password, Authy, or another TOTP app. Then enter the current code to finish setup."
                  )}
                </p>
                <.form
                  for={@two_factor_form}
                  id="settings-enable-two-factor-form"
                  phx-submit="enable_two_factor"
                  class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-start"
                >
                  <div class="w-full sm:max-w-56">
                    <.input
                      field={@two_factor_form[:code]}
                      type="text"
                      label={gettext("Six-digit code")}
                      placeholder="000000"
                      inputmode="numeric"
                      autocomplete="one-time-code"
                      maxlength="6"
                      pattern="[0-9]{6}"
                      required
                    />
                  </div>
                  <button
                    id="settings-enable-two-factor-submit"
                    type="submit"
                    class="btn btn-primary btn-sm gap-1.5 sm:mb-2"
                  >
                    <.icon name="icon-[tabler--shield-check]" class="size-4" />
                    {gettext("Enable 2FA")}
                  </button>
                </.form>
              </div>
            </div>
          <% end %>
        </div>
      </.settings_section>
    </div>
    """
  end

  attr(:integrations, :any, required: true)
  attr(:backfill_form, :map, required: true)
  attr(:gmail_signature_importing_id, :any, required: true)

  defp mail_panel(assigns) do
    loading = is_nil(assigns.integrations)
    gmail_integrations = gmail_integrations(assigns.integrations)

    assigns =
      assigns
      |> assign(:loading, loading)
      |> assign(:gmail_integrations, gmail_integrations)
      |> assign(
        :backfill_integration,
        backfill_integration(gmail_integrations, assigns.backfill_form)
      )

    ~H"""
    <div role="tabpanel" aria-labelledby="settings-tab-mail">
      <%= if not @loading and @gmail_integrations == [] do %>
        <div
          id="mail-configuration-required"
          role="alert"
          class="flex flex-col gap-4 rounded-xl border border-warning/30 bg-warning/10 p-4 sm:flex-row sm:items-center sm:justify-between"
        >
          <div class="flex items-start gap-3">
            <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-warning/15 text-warning">
              <.icon name="icon-[tabler--mail-exclamation]" class="size-5" />
            </div>
            <div>
              <h2 class="text-sm font-semibold text-base-content">
                {gettext("Mail is not configured")}
              </h2>
              <p class="mt-0.5 text-sm leading-relaxed text-base-content/65">
                {gettext("Connect Gmail in General before importing message history.")}
              </p>
            </div>
          </div>
          <button
            type="button"
            id="mail-configure-gmail-btn"
            class="btn btn-primary btn-sm shrink-0 gap-1.5 self-start sm:self-auto"
            phx-click="switch_tab"
            phx-value-tab="general"
          >
            <.icon name="icon-[tabler--settings]" class="size-4" />
            {gettext("Configure mail")}
          </button>
        </div>
      <% else %>
        <.settings_section
          title={gettext("Mail")}
          subtitle={gettext("Import historical messages and tune mailbox defaults.")}
          icon="icon-[tabler--mail-cog]"
        >
          <%= cond do %>
            <% @loading -> %>
              <div
                id="gmail-backfill-loading"
                class="h-72 animate-pulse rounded-xl border border-base-content/10 bg-base-content/8"
              />
            <% true -> %>
              <div class="space-y-4">
                <.form
                  for={@backfill_form}
                  id="gmail-backfill-form"
                  phx-change="validate_gmail_backfill"
                  phx-submit="enqueue_gmail_backfill"
                  class="space-y-4 rounded-xl border border-base-content/10 bg-base-100 p-4 shadow-sm"
                >
                  <div class="flex items-start gap-3">
                    <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                      <.icon name="icon-[tabler--database-import]" class="size-5" />
                    </div>
                    <div>
                      <h3 class="text-sm font-semibold text-base-content">
                        {gettext("Import Gmail history")}
                      </h3>
                      <p class="text-sm leading-relaxed text-base-content/60">
                        {gettext("Runs in the background and skips emails already synced.")}
                      </p>
                    </div>
                  </div>

                  <.gmail_backfill_status integration={@backfill_integration} />

                  <.input
                    field={@backfill_form[:integration_id]}
                    type="select"
                    label={gettext("Email account")}
                    options={gmail_import_options(@gmail_integrations)}
                  />

                  <fieldset>
                    <legend class="mb-2 text-sm font-medium text-base-content">
                      {gettext("Between dates")}
                    </legend>
                    <div class="grid gap-3 sm:grid-cols-2">
                      <.input
                        field={@backfill_form[:start_date]}
                        type="date"
                        label={gettext("Start date")}
                      />
                      <.input
                        field={@backfill_form[:end_date]}
                        type="date"
                        label={gettext("End date")}
                      />
                    </div>
                  </fieldset>

                  <button
                    type="submit"
                    id="gmail-backfill-submit"
                    class="btn btn-primary btn-sm w-full gap-1.5 sm:w-auto"
                    phx-disable-with={gettext("Queueing...")}
                  >
                    <.icon name="icon-[tabler--cloud-upload]" class="size-4" />
                    {gettext("Start import")}
                  </button>
                </.form>
              </div>

              <div id="mail-signature-accounts" class="space-y-3">
                <.mail_signature_import
                  :for={integration <- @gmail_integrations}
                  integration={integration}
                  importing?={@gmail_signature_importing_id == integration.id}
                />
              </div>
          <% end %>
        </.settings_section>
      <% end %>
    </div>
    """
  end

  attr(:integration, :any, required: true)

  defp gmail_backfill_status(assigns) do
    ~H"""
    <div
      :if={@integration && @integration.history_import_status != "idle"}
      id="gmail-backfill-status"
      class={[
        "flex items-start gap-2.5 rounded-lg border px-3 py-2.5 text-sm",
        gmail_backfill_status_class(@integration.history_import_status)
      ]}
    >
      <.icon
        name={gmail_backfill_status_icon(@integration.history_import_status)}
        class="mt-0.5 size-4 shrink-0"
      />
      <div>
        <p class="font-medium">{gmail_backfill_status_title(@integration)}</p>
        <p class="mt-0.5 text-xs opacity-75">{gmail_backfill_status_detail(@integration)}</p>
      </div>
    </div>
    """
  end

  attr(:integration, :map, required: true)
  attr(:importing?, :boolean, required: true)

  defp mail_signature_import(assigns) do
    ~H"""
    <div
      id={"mail-signature-import-#{@integration.id}"}
      class="rounded-xl border border-base-content/10 bg-base-100 p-4 shadow-sm"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div class="flex items-start gap-3">
          <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-secondary/10 text-secondary">
            <.icon name="icon-[tabler--signature]" class="size-5" />
          </div>
          <div>
            <h3 class="text-sm font-semibold text-base-content">
              {gettext("Gmail signature")}
            </h3>
            <p class="text-sm leading-relaxed text-base-content/60">
              {@integration.email_address}
            </p>
          </div>
        </div>
        <button
          type="button"
          id={"mail-import-gmail-signature-#{@integration.id}"}
          phx-click="fetch_gmail_signature"
          phx-value-id={@integration.id}
          disabled={@importing?}
          class="btn btn-outline btn-neutral btn-sm gap-1.5 phx-click-loading:opacity-60 disabled:cursor-wait"
        >
          <.icon
            name={if(@importing?, do: "icon-[tabler--loader-2]", else: "icon-[tabler--download]")}
            class={["size-4", @importing? && "animate-spin"]}
          />
          <span>
            {if(@importing?,
              do: gettext("Importing signature"),
              else: gettext("Import Gmail signature")
            )}
          </span>
        </button>
      </div>
    </div>
    """
  end

  attr(:form, :any, required: true)

  defp automation_panel(assigns) do
    ~H"""
    <div role="tabpanel" aria-labelledby="settings-tab-automation" class="space-y-8">
      <.settings_section
        title={gettext("Clear old review items")}
        subtitle={gettext("Choose how long AI suggestions can wait for your review.")}
        icon="icon-[tabler--clock-x]"
      >
        <div class="rounded-xl border border-base-content/10 bg-base-200/35 p-5">
          <div class="flex items-start gap-3">
            <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
              <.icon name="icon-[tabler--clock-x]" class="size-5" />
            </div>
            <p class="pt-1 text-sm leading-6 text-base-content/60">
              {gettext(
                "Task suggestions and email drafts that are still waiting for your review are rejected automatically after this time."
              )}
            </p>
          </div>

          <.form
            for={@form}
            id="settings-automation-review-cleanup-form"
            phx-submit="update_approval_expiry"
            class="mt-5 flex flex-col gap-4 border-t border-base-content/10 pt-5 sm:flex-row sm:items-end"
          >
            <div class="w-full sm:w-56">
              <.input
                field={@form[:approval_expiry_days]}
                type="number"
                min="1"
                max="90"
                label={gettext("Reject after days")}
              />
            </div>
            <button
              id="settings-automation-review-cleanup-submit"
              type="submit"
              class="btn btn-primary gap-1.5 sm:mb-0.5"
            >
              <.icon name="icon-[tabler--device-floppy]" class="size-4" />
              {gettext("Save")}
            </button>
          </.form>
        </div>
      </.settings_section>
    </div>
    """
  end

  attr(:form, :any, required: true)
  attr(:provider_forms, :map, required: true)
  attr(:provider_usage, :list, required: true)
  attr(:model_usage, :list, required: true)

  defp ai_panel(assigns) do
    ~H"""
    <div role="tabpanel" aria-labelledby="settings-tab-ai" class="space-y-8">
      <.settings_section
        title={gettext("AI behavior")}
        subtitle={
          gettext("Give Konevo the context and writing rules it should use across AI features.")
        }
        icon="icon-[tabler--sparkles]"
      >
        <.form
          for={@form}
          id="settings-ai-preferences-form"
          phx-submit="update_ai_preferences"
          class="space-y-4"
        >
          <div class="grid gap-4 lg:grid-cols-2">
            <.input
              field={@form[:workspace_context]}
              type="textarea"
              label={gettext("AI context")}
              placeholder={
                gettext(
                  "I use this inbox for business inquiries for Company XYZ. We sell custom furniture, mostly B2B. Prioritize delivery timelines, pricing questions, and warm professional replies."
                )
              }
              rows="6"
            />
            <.input
              field={@form[:email_instructions]}
              type="textarea"
              label={gettext("Email behavior")}
              placeholder={
                gettext(
                  "Keep replies short. Do not sound too salesy. Ask one clear follow-up question when details are missing. Never promise dates unless they are in the thread."
                )
              }
              rows="6"
            />
          </div>

          <div class="grid gap-4 md:grid-cols-3">
            <.input
              field={@form[:tone]}
              type="select"
              label={gettext("Tone")}
              options={[
                {gettext("Professional"), "professional"},
                {gettext("Friendly"), "friendly"},
                {gettext("Direct"), "direct"},
                {gettext("Warm"), "warm"}
              ]}
            />
            <.input
              field={@form[:language]}
              type="select"
              label={gettext("Language")}
              options={[
                {gettext("Same as incoming email"), "auto"},
                {gettext("English"), "English"},
                {gettext("Slovak"), "Slovak"}
              ]}
            />
            <.input
              field={@form[:response_length]}
              type="select"
              label={gettext("Response length")}
              options={[
                {gettext("Concise"), "concise"},
                {gettext("Balanced"), "balanced"},
                {gettext("Detailed"), "detailed"}
              ]}
            />
          </div>

          <.input
            field={@form[:custom_instruction]}
            type="textarea"
            label={gettext("Instructions")}
            placeholder={
              gettext(
                "For example: lead with the decision, avoid sales language, and offer two meeting times."
              )
            }
            rows="5"
          />

          <div class="mt-4 flex justify-end">
            <button
              id="settings-ai-preferences-submit"
              type="submit"
              class="btn btn-primary btn-sm gap-2"
            >
              <.icon name="icon-[tabler--device-floppy]" class="size-4" />
              {gettext("Save preferences")}
            </button>
          </div>
        </.form>
      </.settings_section>

      <.settings_section
        title={gettext("OpenAI")}
        subtitle={gettext("Save your API key and review this month's model usage.")}
        icon="icon-[tabler--key]"
      >
        <div class="grid items-start gap-4 xl:grid-cols-2">
          <.provider_setting_card
            :for={summary <- @provider_usage}
            summary={summary}
            form={@provider_forms[summary.provider_value]}
          />
          <.provider_usage_card
            :for={summary <- @provider_usage}
            summary={summary}
            usage={@model_usage}
          />
        </div>
      </.settings_section>
    </div>
    """
  end

  attr(:summary, :map, required: true)
  attr(:form, :any, required: true)

  defp provider_setting_card(assigns) do
    ~H"""
    <div
      id={"settings-ai-provider-settings-#{@summary.provider_value}"}
      class="overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm"
    >
      <div class="border-b border-base-content/10 bg-base-200/35 p-4">
        <div class="flex items-start justify-between gap-3">
          <div class="flex items-start gap-3">
            <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
              <.icon name={provider_icon(@summary.provider)} class="size-5" />
            </div>
            <div>
              <h3 class="text-sm font-semibold text-base-content">
                {provider_title(@summary.provider)}
              </h3>
              <p class="text-sm leading-6 text-base-content/60">
                {provider_description(@summary.provider)}
              </p>
            </div>
          </div>
          <span
            class={[
              "badge badge-sm shrink-0 rounded-md border",
              not @summary.has_api_key? && "border-warning/30 bg-warning/10 text-warning"
            ]}
            style={if(@summary.has_api_key?, do: integration_status_style(true))}
          >
            {key_status(@summary)}
          </span>
        </div>
      </div>

      <div class="p-4">
        <.form
          for={@form}
          id={"settings-ai-provider-#{@summary.provider_value}-form"}
          phx-submit="update_ai_provider_settings"
          class="space-y-4"
        >
          <input
            type="hidden"
            id={"settings-ai-provider-#{@summary.provider_value}-provider"}
            name={@form[:provider].name}
            value={@summary.provider_value}
          />
          <.input
            id={"settings-ai-provider-#{@summary.provider_value}-api-key"}
            field={@form[:api_key]}
            type="password"
            label={gettext("API key")}
            placeholder={api_key_placeholder(@summary)}
            autocomplete="off"
            spellcheck="false"
          />
          <%= if is_binary(@summary.api_key_mask) do %>
            <p
              id={"settings-ai-provider-#{@summary.provider_value}-key-hint"}
              class="text-xs text-base-content/60"
            >
              {gettext("Saved key:")}
              <span class="font-mono font-medium text-base-content">{@summary.api_key_mask}</span>
            </p>
          <% end %>
          <.input
            id={"settings-ai-budget-#{@summary.provider_value}"}
            field={@form[:monthly_budget]}
            type="hidden"
          />
          <div class="flex justify-end pt-2">
            <button
              id={"settings-ai-provider-#{@summary.provider_value}-submit"}
              type="submit"
              class="btn btn-primary btn-sm w-full gap-1.5 sm:w-auto"
              phx-disable-with={gettext("Saving...")}
            >
              <.icon name="icon-[tabler--device-floppy]" class="size-4" />
              {gettext("Save provider")}
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr(:summary, :map, required: true)
  attr(:usage, :list, required: true)

  defp provider_usage_card(assigns) do
    ~H"""
    <div
      id={"settings-ai-usage-#{@summary.provider_value}"}
      class="overflow-hidden rounded-xl border border-base-content/10 bg-base-100 shadow-sm"
    >
      <div class="border-b border-base-content/10 bg-base-200/35 p-4">
        <div class="flex items-start justify-between gap-3">
          <div class="flex items-start gap-3">
            <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
              <.icon name="icon-[tabler--chart-bar]" class="size-5" />
            </div>
            <div>
              <h3 class="text-sm font-semibold text-base-content">{gettext("Token usage")}</h3>
              <p class="text-sm leading-6 text-base-content/60">
                {gettext("This month's OpenAI usage.")}
              </p>
            </div>
          </div>
          <p class="shrink-0 pt-0.5 text-xs text-base-content/50">
            {gettext("Since")} {period_label(@summary.period_start)}
          </p>
        </div>
      </div>

      <div class="p-4">
        <p class="text-sm font-medium text-base-content">
          {format_tokens(@summary.total_tokens)}
        </p>

        <div class="mt-4 grid grid-cols-2 gap-x-4 gap-y-3 text-xs">
          <div>
            <p class="text-base-content/50">{gettext("Input")}</p>
            <p class="font-medium text-base-content">{format_tokens(@summary.input_tokens)}</p>
          </div>
          <div>
            <p class="text-base-content/50">{gettext("Output")}</p>
            <p class="font-medium text-base-content">{format_tokens(@summary.output_tokens)}</p>
          </div>
          <div>
            <p class="text-base-content/50">{gettext("Runs")}</p>
            <p class="font-medium text-base-content">{format_tokens(@summary.runs)}</p>
          </div>
          <div>
            <p class="text-base-content/50">{gettext("Money spent")}</p>
            <p class="font-medium text-base-content">{format_money(@summary.estimated_spend, 4)}</p>
          </div>
        </div>
      </div>

      <.model_usage_card usage={@usage} embedded />
    </div>
    """
  end

  attr(:usage, :list, required: true)
  attr(:embedded, :boolean, default: false)

  defp model_usage_card(assigns) do
    total_tokens = Enum.sum(Enum.map(assigns.usage, & &1.total_tokens))
    assigns = assign(assigns, :total_tokens, total_tokens)

    ~H"""
    <div
      id="settings-ai-model-usage"
      class={[
        "grid gap-5 sm:grid-cols-[8rem_minmax(0,1fr)] sm:items-center",
        if(@embedded,
          do: "border-t border-base-content/10 p-4",
          else: "rounded-xl border border-base-content/10 bg-base-100 p-4 shadow-sm"
        )
      ]}
    >
      <div class="mx-auto">
        <div
          role="img"
          aria-label={gettext("Token usage split between Terra and Luna")}
          class="flex size-32 items-center justify-center rounded-full p-3 shadow-inner"
          style={model_usage_chart_style(@usage)}
        >
          <div class="flex size-full flex-col items-center justify-center rounded-full bg-base-100 text-center">
            <span class="text-[0.65rem] font-semibold uppercase tracking-wide text-base-content/50">
              {gettext("Tokens")}
            </span>
            <span class="mt-0.5 text-sm font-semibold text-base-content">
              {format_tokens(@total_tokens)}
            </span>
          </div>
        </div>
      </div>

      <div class="space-y-3">
        <div :for={model <- @usage} class="flex items-center justify-between gap-4">
          <div class="flex min-w-0 items-center gap-2.5">
            <span class={["size-2.5 shrink-0 rounded-full", model_usage_color(model.id)]} />
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-base-content">{model.label}</p>
              <p class="text-xs text-base-content/55">
                {format_tokens(model.runs)} {gettext("runs")} · {format_money(
                  model.estimated_spend,
                  4
                )}
              </p>
            </div>
          </div>
          <div class="shrink-0 text-right">
            <p class="text-sm font-semibold text-base-content">
              {model_usage_percentage(@usage, model.id)}%
            </p>
            <p class="text-xs text-base-content/55">{format_tokens(model.total_tokens)}</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp provider_icon(:openai_responses), do: "icon-[tabler--brand-openai]"
  defp provider_icon(_provider), do: "icon-[tabler--sparkles]"

  defp provider_title(:openai_responses), do: gettext("OpenAI")
  defp provider_title(_provider), do: gettext("AI provider")

  defp provider_description(:openai_responses),
    do: gettext("Terra handles quality-focused work; Luna handles high-volume tasks.")

  defp provider_description(_provider), do: gettext("Used for AI tasks.")

  defp key_status(%{has_api_key?: true}), do: gettext("Saved")
  defp key_status(_summary), do: gettext("No key")

  defp api_key_placeholder(%{has_api_key?: true}), do: gettext("Leave blank to keep saved key")
  defp api_key_placeholder(_summary), do: gettext("Paste API key")

  defp model_usage_chart_style(usage) do
    case Enum.sum(Enum.map(usage, & &1.total_tokens)) do
      0 ->
        "background: var(--color-base-300)"

      _total ->
        terra_share = model_usage_percentage(usage, :terra)

        "background: conic-gradient(var(--color-primary) 0 #{terra_share}%, #93c5fd #{terra_share}% 100%)"
    end
  end

  defp model_usage_percentage(usage, model_id) do
    total_tokens = Enum.sum(Enum.map(usage, & &1.total_tokens))

    model_tokens =
      usage |> Enum.find(%{total_tokens: 0}, &(&1.id == model_id)) |> Map.get(:total_tokens)

    if total_tokens == 0 do
      0
    else
      round(model_tokens / total_tokens * 100)
    end
  end

  defp model_usage_color(:terra), do: "bg-primary"
  defp model_usage_color(:luna), do: "bg-blue-300"
  defp model_usage_color(_model), do: "bg-base-content/30"

  defp format_tokens(value) when is_integer(value), do: Integer.to_string(value)
  defp format_tokens(_value), do: "0"

  defp format_money(%Decimal{} = value, scale) do
    "$" <> (value |> Decimal.round(scale) |> Decimal.to_string(:normal))
  end

  defp format_money(_value, scale), do: format_money(Decimal.new("0.00"), scale)

  defp period_label(%DateTime{} = period_start), do: Calendar.strftime(period_start, "%b %-d")
  defp period_label(_period_start), do: ""
end
