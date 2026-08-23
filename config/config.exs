# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :konevo, :scopes,
  user: [
    default: true,
    module: Konevo.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Konevo.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :konevo,
  ecto_repos: [Konevo.Repo],
  generators: [timestamp_type: :utc_datetime],
  default_tenant_slug: "public",
  support_email: "support@example.com",
  mailer_from: {"Konevo", "contact@example.com"}

config :konevo, :ai,
  provider: Konevo.AI.LangChainProvider,
  models: %{
    fast: %{
      provider: :openai_responses,
      model: "gpt-5.6-luna",
      api_key: nil,
      reasoning: %{effort: :low}
    },
    standard: %{
      provider: :openai_responses,
      model: "gpt-5.6-terra",
      api_key: nil,
      reasoning: %{effort: :medium}
    },
    premium: %{
      provider: :openai_responses,
      model: "gpt-5.6-terra",
      api_key: nil,
      reasoning: %{effort: :high}
    }
  }

config :konevo, :company_intel,
  provider: nil,
  source: nil

config :phoenix_live_view, :colocated_js, disable_symlink_warning: true

config :konevo, Konevo.Oban,
  engine: Oban.Engines.Basic,
  repo: Konevo.Repo,
  queues: [
    default: 10
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"*/5 * * * *", Konevo.Workers.GmailSyncWorker},
       {"* * * * *", Konevo.Workers.ScheduledEmailRecoveryWorker},
       {"* * * * *", Konevo.Workers.NoReplyFollowUpWorker},
       {"0 * * * *", Konevo.Workers.ApprovalExpiryWorker},
       {"*/10 * * * *", Konevo.Workers.UploadDeleteCleanupWorker}
     ]}
  ]

# Configure the endpoint
config :konevo, KonevoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KonevoWeb.ErrorHTML, json: KonevoWeb.ErrorJSON],
    layout: {KonevoWeb.Layouts, :root}
  ],
  pubsub_server: Konevo.PubSub,
  live_view: [signing_salt: "WRnrp+Zb"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :konevo, Konevo.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  konevo: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  konevo: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :mime, :types, %{
  "audio/ogg" => ["ogg"]
}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
