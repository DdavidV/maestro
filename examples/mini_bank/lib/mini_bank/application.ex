defmodule MiniBank.Application do
  @moduledoc false
  use Application
  require Logger

  @workspace_name "MiniBank"
  @workspace_id "minibank"
  @workspace_root Path.expand("../../priv/workspace", __DIR__)

  @impl true
  def start(_type, _args) do
    case Maestro.Workspaces.get(@workspace_id) do
      {:ok, _workspace} ->
        :ok

      {:error, :not_found} ->
        {:ok, _workspace} = Maestro.Workspaces.create(@workspace_name, @workspace_root)
    end

    children = [MiniBank.Bank, MiniBank.Wire.Server, MiniBank.Http.Endpoint]
    opts = [strategy: :one_for_one, name: MiniBank.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
