defmodule MiniBank.Http.Endpoint do
  @moduledoc false

  use GenServer

  @persistent_term_key {__MODULE__, :port}

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec port() :: :inet.port_number()
  def port, do: :persistent_term.get(@persistent_term_key)

  @impl true
  def init(_opts) do
    {:ok, bandit_pid} =
      Bandit.start_link(plug: MiniBank.Http.Router, ip: {127, 0, 0, 1}, port: 0)

    {:ok, {_address, port}} = ThousandIsland.listener_info(bandit_pid)
    :persistent_term.put(@persistent_term_key, port)

    {:ok, %{bandit_pid: bandit_pid}}
  end
end
