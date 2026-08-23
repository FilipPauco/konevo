defmodule Konevo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KonevoWeb.Telemetry,
      Konevo.Repo,
      Konevo.Oban,
      {DNSCluster, query: Application.get_env(:konevo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Konevo.PubSub},
      Konevo.Security.RateLimiter,
      # Start a worker by calling: Konevo.Worker.start_link(arg)
      # {Konevo.Worker, arg},
      # Start to serve requests, typically the last entry
      KonevoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Konevo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KonevoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
