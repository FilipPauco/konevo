defmodule KonevoWeb.Router do
  use KonevoWeb, :router

  import KonevoWeb.UserAuth

  alias KonevoWeb.Plugs.{
    LoadOrganization,
    LoadPermissions,
    RequireMembership,
    RequireTenantAccessIfAuthenticated,
    SetTenantContext
  }

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {KonevoWeb.Layouts, :root})
    plug(:protect_from_forgery)

    plug(:put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: blob: https://*.googleusercontent.com; font-src 'self' https://fonts.gstatic.com; connect-src 'self' ws: wss:; frame-ancestors 'none'"
    })

    plug(:fetch_current_scope_for_user)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :public_auth_rate_limit do
    plug(KonevoWeb.Plugs.AuthRateLimit)
  end

  # Loads the org from subdomain, verifies membership, enriches scope with role,
  # and sets the Postgres RLS tenant context.
  pipeline :org_scoped do
    plug(LoadOrganization)
    plug(RequireMembership)
    plug(LoadPermissions)
    plug(SetTenantContext)
  end

  pipeline :tenant_access_if_authenticated do
    plug(LoadOrganization)
    plug(RequireTenantAccessIfAuthenticated)
  end

  # Other scopes may use custom stacks.
  # scope "/api", KonevoWeb do
  #   pipe_through :api
  # end

  scope "/", KonevoWeb do
    get("/robots.txt", SeoController, :robots)
    get("/sitemap.xml", SeoController, :sitemap)
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:konevo, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: KonevoWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  ## Authentication routes — user account management (no org required)

  scope "/", KonevoWeb do
    pipe_through([
      :browser,
      :require_authenticated_user,
      :tenant_access_if_authenticated
    ])

    post("/users/update-password", UserSessionController, :update_password)
  end

  ## Org-scoped routes — require an active org membership

  scope "/", KonevoWeb do
    pipe_through([:browser, :require_authenticated_user, :org_scoped])

    live_session :require_authenticated_user_in_org,
      on_mount: [
        {KonevoWeb.UserAuth, :require_authenticated},
        {KonevoWeb.Nav, :default},
        {KonevoWeb.SessionHooks, :load_org_scope},
        {KonevoWeb.SessionHooks, :subscribe_session},
        {KonevoWeb.SessionHooks, :verify_token_on_event}
      ] do
      live("/dashboard", HomeLive, :index)
      live("/contacts", ContactsLive.Index, :index)
      live("/contacts/new", ContactsLive.Index, :new)
      live("/contacts/:id", ContactsLive.Show, :show)
      live("/contacts/:id/edit", ContactsLive.Show, :edit)
      live("/contacts/:id/edit/inline", ContactsLive.Index, :edit)

      live("/companies", CompaniesLive.Index, :index)
      live("/companies/new", CompaniesLive.Index, :new)
      live("/companies/:id", CompaniesLive.Show, :show)
      live("/companies/:id/edit", CompaniesLive.Show, :edit)
      live("/companies/:id/edit/inline", CompaniesLive.Index, :edit)

      live("/deals", DealsLive.Index, :index)
      live("/deals/new", DealsLive.Index, :new)
      live("/deals/:id/edit", DealsLive.Index, :edit)

      live("/inbox", InboxLive.Index, :index)
      live("/inbox/:id", InboxLive.Show, :show)
      live("/inbox/:id/contact/new", InboxLive.Show, :new_contact)
      live("/inbox/:id/company/new", InboxLive.Show, :new_company)
      live("/inbox/:id/task/new", InboxLive.Show, :new_task)
      live("/inbox/:id/deal/new", InboxLive.Show, :new_deal)

      live("/tasks", TasksLive.Index, :index)
      live("/tasks/new", TasksLive.Index, :new)
      live("/tasks/new/:parent_id", TasksLive.Index, :new)
      live("/tasks/:id", TasksLive.Index, :detail)

      live("/automation", AutomationLive.Index, :index)

      live("/calendar", CalendarLive.Index, :index)
      live("/calendar/tasks/:task_id", CalendarLive.Index, :task)

      live("/team", TeamLive.Index, :index)
      # Temporarily disabled until support requests are re-enabled.
      # live("/support", SupportLive, :index)
      live("/settings", SettingsLive, :index)
      live("/uploads/documents", DocumentUploadLive, :index)
      live("/tenants", TenantLive.Index, :index)
      live("/tenants/new", TenantLive.Index, :new)

      get("/integrations/gmail/consent", GmailAuthController, :consent)
      post("/integrations/gmail/consent", GmailAuthController, :confirm_consent)
    end

    # File serving routes (authenticated, per-request authorization)
    get("/uploads/:context/:id", UploadController, :show)

    # Gmail OAuth — connect requires org context (to know which org to link)
    get("/integrations/gmail/connect", GmailAuthController, :connect)
  end

  scope "/", KonevoWeb do
    pipe_through([:browser, :require_authenticated_user])

    # Gmail OAuth callback — no org_scoped pipeline; Google sends back to fixed URL
    # (may be called on bare localhost without subdomain). Org is loaded from session.
    get("/integrations/gmail/callback", GmailAuthController, :callback)
  end

  scope "/", KonevoWeb do
    pipe_through([:browser])

    live_session :current_user,
      on_mount: [{KonevoWeb.UserAuth, :mount_current_scope}, {KonevoWeb.Nav, :default}] do
      # Public presentation. It works without authentication while signed-in users
      # still receive their normal scope.
      live("/", TestLandingLive, :index)
      live("/users/log-in", UserLive.Login, :new)
      live("/users/log-in/:token", UserLive.Confirmation, :new)
      live("/users/two-factor", UserLive.TwoFactor, :new)
      live("/users/reset-password", UserLive.PasswordResetRequest, :new)
      live("/users/reset-password/:token", UserLive.PasswordReset, :edit)
      live("/tenant-invitations/:token", TenantInvitationLive.Accept, :show)
    end

    get("/privacy", LegalController, :privacy)
    get("/terms", LegalController, :terms)

    delete("/users/log-out", UserSessionController, :delete)
  end

  scope "/", KonevoWeb do
    pipe_through([:browser, :public_auth_rate_limit])

    post("/users/log-in", UserSessionController, :create)
    post("/users/two-factor", UserSessionController, :two_factor)
    post("/users/reset-password", UserSessionController, :reset_password)
    post("/tenant-invitations/:token/accept", TenantInvitationController, :accept)
  end
end
