defmodule MiniBank.Wire.Server do
  @moduledoc """
  Listens on `127.0.0.1` on an OS-assigned ephemeral port
  (`:gen_tcp.listen(0, ...)`), and spawns one `MiniBank.Wire.Connection`
  per accepted socket. The chosen port is published via `:persistent_term`
  (written once, right after `:gen_tcp.listen/2` succeeds) so
  `MiniBank.Maestro.WireClient` can discover it without either side
  hardcoding a port number.
  """

  use GenServer
  require Logger

  @persistent_term_key {__MODULE__, :port}

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec port() :: :inet.port_number()
  def port, do: :persistent_term.get(@persistent_term_key)

  @impl true
  def init(_opts) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :line,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, port} = :inet.port(listen_socket)
    :persistent_term.put(@persistent_term_key, port)
    Logger.info("#{__MODULE__} listening on 127.0.0.1:#{port}")

    send(self(), :accept)
    {:ok, %{listen_socket: listen_socket}}
  end

  @impl true
  def handle_info(:accept, %{listen_socket: listen_socket} = state) do
    case :gen_tcp.accept(listen_socket, 200) do
      {:ok, client_socket} ->
        {:ok, pid} = MiniBank.Wire.Connection.start(client_socket)
        :ok = :gen_tcp.controlling_process(client_socket, pid)

      {:error, :timeout} ->
        :ok
    end

    send(self(), :accept)
    {:noreply, state}
  end
end
