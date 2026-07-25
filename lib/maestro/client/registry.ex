defmodule Maestro.Client.Registry do
  @moduledoc """
  Discovers `Maestro.Client` implementations and runs their `init_client/0`.

  Discovery (via `Maestro.Core.BehaviourDiscovery`) scans every module
  currently loaded into the VM for one implementing the `Maestro.Client`
  behaviour `use Maestro.Client, name: "..."` is all a client needs to be
  found, no explicit registration list to maintain.
  `init_client/0` (if the module implements it) runs once per
  discovered module, the first time the registry loads, its result is
  memoized in `:persistent_term` alongside the module itself, so `fetch/1`
  never touches it again.

  A client whose `init_client/0` fails doesn't take the registry down
  every other client still registers normally, and `fetch/1` for the
  failing one returns `{:error, {:init_failed, reason}}`. One broken
  client (an unreachable dependency at boot, a failed connection pool
  start) failing shouldn't make every *other* client unusable.
  """

  @persistent_term_key {__MODULE__, :clients}

  @type entry :: %{module: module, state: term}
  @type reason :: :not_found | {:init_failed, term}

  @doc """
  Discovers every `Maestro.Client` implementation, runs `init_client/0` for
  each, and caches the result in `:persistent_term`.

  Safe to call more than once (e.g. to pick up clients from an application
  started after Maestro's own boot) each call rediscovers and replaces
  the cached table from scratch.
  """
  @spec load! :: :ok
  def load! do
    clients = discover() |> Map.new(fn module -> {module.name(), build_entry(module)} end)
    :persistent_term.put(@persistent_term_key, clients)
    :ok
  end

  @doc """
  Fetches the registered client for `name`.

  Triggers `load!/0` on first use if it hasn't run yet, so this is safe to
  call regardless of application boot order the caller never needs to
  know whether `Maestro.Application` already ran discovery.
  """
  @spec fetch(String.t()) :: {:ok, entry} | {:error, reason}
  def fetch(name) when is_binary(name) do
    clients =
      case :persistent_term.get(@persistent_term_key, :not_loaded) do
        :not_loaded ->
          :ok = load!()
          :persistent_term.get(@persistent_term_key)

        clients ->
          clients
      end

    case Map.fetch(clients, name) do
      {:ok, {:ok, entry}} -> {:ok, entry}
      {:ok, {:error, init_reason}} -> {:error, {:init_failed, init_reason}}
      :error -> {:error, :not_found}
    end
  end

  defp build_entry(module) do
    case init_client_state(module) do
      {:ok, state} -> {:ok, %{module: module, state: state}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp init_client_state(module) do
    if function_exported?(module, :init_client, 0) do
      module.init_client()
    else
      {:ok, nil}
    end
  end

  defp discover do
    Maestro.Core.BehaviourDiscovery.modules_implementing(Maestro.Client)
  end
end
