defmodule Maestro.Client do
  @moduledoc """
  Behaviour for a Maestro client: something that knows how to send a
  rendered template through a protocol (HTTP, Kafka, gRPC, raw TCP, ...).

  `use Maestro.Client, name: "http"` is enough to register a module.

  Three callbacks, two of them optional:

    * `init_client/0` called once ever, the first time this client is
      discovered.
      It's for infrastructure the client needs regardless of any
      particular step (starting a supervised GenServer, opening a DB connection pool, ...),
      not for per-call configuration. Returns a `client_state` that's memoized for the
      lifetime of the application.

    * `init/2` called once per step execution, before `send/2`. Receives
      the memoized `client_state` and the step's rendered template
      (`t:rendered/0` the template's `payload` and `options`, with every
      `{{placeholder}}` already filled in from the resolved dataset). This
      is where per-call configuration lives it comes from the step
      itself, via `rendered["options"]`.
      Returns a `call_state` that `send/2` will use.

    * `send/2` called once per step execution, immediately after `init/2`.
      Receives `call_state` and the same `rendered` template
      `init/2` saw, and actually performs the send.
  """

  @type rendered :: %{String.t() => term}

  @callback name() :: String.t()
  @callback init_client() :: {:ok, client_state :: term} | {:error, term}
  @callback init(client_state :: term, rendered) :: {:ok, call_state :: term} | {:error, term}
  @callback send(call_state :: term, rendered) :: {:ok, response :: term} | {:error, term}

  @optional_callbacks init_client: 0, init: 2

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)

    quote do
      @behaviour Maestro.Client
      @maestro_client_name unquote(name)
      @impl true
      def name, do: @maestro_client_name
    end
  end
end
