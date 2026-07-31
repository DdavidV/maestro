defmodule Maestro.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    configure_runtime()

    Maestro.Resources.Schemas.load!()
    Maestro.Resources.SchemaDocs.load!()
    Maestro.Client.Registry.load!()
    Maestro.Assert.Registry.load!()
    Maestro.Generator.Registry.load!()

    children =
      [
        MaestroWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:maestro, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Maestro.PubSub},
        Maestro.Core.Runner.Store,
        Maestro.Workspaces.Store,
        {Task.Supervisor, name: Maestro.Core.Runner.TaskSupervisor}
      ] ++ endpoint_child()

    opts = [strategy: :one_for_one, name: Maestro.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp configure_runtime do
    # ex_json_schema configuration
    Application.put_env(:ex_json_schema, :decode_json, &Jason.decode/1)

    Application.put_env(
      :ex_json_schema,
      :remote_schema_resolver,
      {Maestro.Resources.Schemas, :load_and_resolve_ref}
    )

    # maestro configuration
    endpoint_config = Application.get_env(:maestro, MaestroWeb.Endpoint, [])

    default_endpoint_config = [
      url: [host: "localhost"],
      adapter: Bandit.PhoenixAdapter,
      http: [ip: {127, 0, 0, 1}, port: 4000],
      server: true,
      secret_key_base: Base.encode64(:crypto.strong_rand_bytes(48)),
      pubsub_server: Maestro.PubSub,
      live_view: [signing_salt: "XzGKx7gj"],
      render_errors: [
        formats: [html: MaestroWeb.ErrorHTML, json: MaestroWeb.ErrorJSON],
        layout: false
      ]
    ]

    merged_endpoint_config = Keyword.merge(default_endpoint_config, endpoint_config)
    Application.put_env(:maestro, MaestroWeb.Endpoint, merged_endpoint_config)
  end

  defp endpoint_child do
    if Application.get_env(:maestro, :start_endpoint?, true) do
      [MaestroWeb.Endpoint]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MaestroWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
