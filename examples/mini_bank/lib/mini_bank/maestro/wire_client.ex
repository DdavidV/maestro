defmodule MiniBank.Maestro.WireClient do
  @moduledoc """
  Maestro client for MiniBank's own newline-delimited-JSON wire protocol
  (`MiniBank.Wire.Server`/`MiniBank.Wire.Connection`), registered as
  `"wire"`.

  A step using this client writes its request as an ordinary template
  `payload`:

  ```json
  {
    "clients": ["wire"],
    "payload": {
      "op": "open_account",
      "args": { "account_number": "{{account_number}}", "owner": "{{owner}}", "initial_balance": 10000 }
    }
  }
  ```

  `send/2` opens a fresh short-lived `:gen_tcp` connection to
  `MiniBank.Wire.Server.port()` on localhost per call,
  writes one NDJSON request line, reads exactly one NDJSON response line,
  decodes it, and closes the socket.
  Returns `{:ok, response}` where `response` is the decoded
  response map this becomes `actual` for every assertion on a `"wire"` step.

  Connection/timeout/decode failures are all `{:error, reason}`, never a
  raise, matching every other Maestro client's documented contract.
  """

  use Maestro.Client, name: "wire"

  @connect_timeout 2_000
  @recv_timeout 2_000

  @impl true
  def send(_call_state, %{"payload" => %{"op" => op, "args" => args}}) do
    host = ~c"127.0.0.1"
    port = MiniBank.Wire.Server.port()

    with {:ok, socket} <-
           :gen_tcp.connect(host, port, [:binary, packet: :line, active: false], @connect_timeout),
         :ok <- :gen_tcp.send(socket, Jason.encode!(%{"op" => op, "args" => args}) <> "\n"),
         {:ok, line} <- :gen_tcp.recv(socket, 0, @recv_timeout),
         {:ok, decoded} <- Jason.decode(String.trim(line)) do
      :gen_tcp.close(socket)
      {:ok, decoded}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def send(_call_state, rendered) do
    {:error, {:invalid_payload, rendered["payload"]}}
  end
end
