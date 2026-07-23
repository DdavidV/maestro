defmodule Maestro.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Maestro.Resources.Schemas.load!()
    Maestro.Client.Registry.load!()
    Maestro.Assert.Registry.load!()

    children = [
      MaestroWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:maestro, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Maestro.PubSub},
      MaestroWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Maestro.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MaestroWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
