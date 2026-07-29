defmodule Maestro.Assert.Registry do
  @moduledoc """
  Discovers `Maestro.Assert.Matcher` implementations.

  Discovery (via `Maestro.Core.BehaviourDiscovery`, shared with
  `Maestro.Client.Registry`) scans every module currently loaded into the VM
  for one implementing the `Maestro.Assert.Matcher` behaviour
  `use Maestro.Assert.Matcher, name: "..."` is all a matcher needs to be
  found, no explicit registration list to maintain. Unlike clients, matchers
  have no one-time setup step (`Maestro.Assert.Matcher` has no
  `init_matcher/0` — matchers are static code), so the cached table is just
  a name-to-module lookup, with no per-module init-failure isolation to
  worry about.

  If more than one discovered module registers the same `name/0`, `load!/0`
  logs a warning (see `Maestro.Core.RegistryCollisions`) rather than
  silently picking one.
  """

  alias Maestro.Core.RegistryCollisions

  @persistent_term_key {__MODULE__, :matchers}

  @type reason :: :not_found

  @doc """
  Discovers every `Maestro.Assert.Matcher` implementation and caches the
  name-to-module table in `:persistent_term`.

  Safe to call more than once each call rediscovers and replaces the
  cached table from scratch.
  """
  @spec load! :: :ok
  def load! do
    entries = discover() |> Enum.map(fn module -> {module.name(), module} end)

    :ok = RegistryCollisions.warn_on_collisions("Maestro.Assert.Registry", entries)

    :persistent_term.put(@persistent_term_key, Map.new(entries))
    :ok
  end

  @doc """
  Fetches the registered matcher module for `name`.

  Triggers `load!/0` on first use if it hasn't run yet, so this is safe to
  call regardless of application boot order.
  """
  @spec fetch(String.t()) :: {:ok, module} | {:error, reason}
  def fetch(name) when is_binary(name) do
    matchers = load_or_get()

    case Map.fetch(matchers, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Every registered matcher name, e.g. for a UI picker/dropdown.

  Triggers `load!/0` on first use, same as `fetch/1`.
  """
  @spec names() :: [String.t()]
  def names, do: load_or_get() |> Map.keys()

  defp load_or_get do
    case :persistent_term.get(@persistent_term_key, :not_loaded) do
      :not_loaded ->
        :ok = load!()
        :persistent_term.get(@persistent_term_key)

      matchers ->
        matchers
    end
  end

  defp discover do
    Maestro.Core.BehaviourDiscovery.modules_implementing(Maestro.Assert.Matcher)
  end
end
