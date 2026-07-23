defmodule Maestro.Assert.Registry do
  @moduledoc """
  Discovers `Maestro.Assert.Matcher` implementations.

  Discovery scans every module currently loaded into the VM for one
  implementing the `Maestro.Assert.Matcher` behaviour
  `use Maestro.Assert.Matcher, name: "..."` is all a matcher needs to be
  found, no explicit registration list to maintain — same mechanism as
  `Maestro.Client.Registry`. Unlike clients, matchers have no one-time setup
  step (`Maestro.Assert.Matcher` has no `init_matcher/0` — matchers are
  static code), so the cached table is just a name-to-module lookup, with
  no per-module init-failure isolation to worry about.
  """

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
    matchers = discover() |> Map.new(fn module -> {module.name(), module} end)
    :persistent_term.put(@persistent_term_key, matchers)
    :ok
  end

  @doc """
  Fetches the registered matcher module for `name`.

  Triggers `load!/0` on first use if it hasn't run yet, so this is safe to
  call regardless of application boot order.
  """
  @spec fetch(String.t()) :: {:ok, module} | {:error, reason}
  def fetch(name) when is_binary(name) do
    matchers =
      case :persistent_term.get(@persistent_term_key, :not_loaded) do
        :not_loaded ->
          :ok = load!()
          :persistent_term.get(@persistent_term_key)

        matchers ->
          matchers
      end

    case Map.fetch(matchers, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :not_found}
    end
  end

  defp discover do
    for {app, _description, _vsn} <- Application.loaded_applications(),
        {:ok, modules} <- [:application.get_key(app, :modules)],
        module <- modules,
        implements_matcher?(module) do
      module
    end
  end

  defp implements_matcher?(module) do
    Code.ensure_loaded?(module) and
      Maestro.Assert.Matcher in (module.module_info(:attributes)[:behaviour] || [])
  end
end
