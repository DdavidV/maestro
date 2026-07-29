defmodule Maestro.Generator.Registry do
  @moduledoc """
  Discovers every `{"$generated": name}` a `Maestro.Generator`-using module
  registers, mirroring `Maestro.Assert.Registry`'s discovery/caching
  approach with two differences: one module can register many names,
  so discovery flat-maps each discovered module's own
  `__maestro_generators__/0` list rather than reading a single `name/0`
  per module and discovery itself doesn't use `Maestro.Core.BehaviourDiscovery`,
  since a generator module declares no callbacks at all
  (generators aren't named, only the generated data is) discovery here
  scans loaded modules directly for an exported `__maestro_generators__/0`,
  the actual marker `use Maestro.Generator` leaves behind.

  If more than one discovered module registers the same name, `load!/0`
  logs a warning (see `Maestro.Core.RegistryCollisions`) rather than
  silently picking one a same-module duplicate is instead a compile
  error, see `Maestro.Generator.__before_compile__/1`.
  """

  alias Maestro.Core.RegistryCollisions

  @persistent_term_key {__MODULE__, :generators}

  @type reason :: :not_found

  @doc """
  Discovers every `Maestro.Generator`-using module's registered names and
  caches the name-to-module table in `:persistent_term`.

  Safe to call more than once each call rediscovers and replaces the
  cached table from scratch.
  """
  @spec load! :: :ok
  def load! do
    entries =
      discover()
      |> Enum.flat_map(fn module ->
        Enum.map(module.__maestro_generators__(), fn {name, _function} -> {name, module} end)
      end)

    :ok = RegistryCollisions.warn_on_collisions("Maestro.Generator.Registry", entries)

    :persistent_term.put(@persistent_term_key, Map.new(entries))
    :ok
  end

  @doc """
  Fetches the registered generator module for `name`.

  Triggers `load!/0` on first use if it hasn't run yet, so this is safe to
  call regardless of application boot order.
  """
  @spec fetch(String.t()) :: {:ok, module} | {:error, reason}
  def fetch(name) when is_binary(name) do
    generators = load_or_get()

    case Map.fetch(generators, name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Every registered generator name, e.g. for a UI picker/dropdown.

  Triggers `load!/0` on first use, same as `fetch/1`.
  """
  @spec names() :: [String.t()]
  def names, do: load_or_get() |> Map.keys()

  defp load_or_get do
    case :persistent_term.get(@persistent_term_key, :not_loaded) do
      :not_loaded ->
        :ok = load!()
        :persistent_term.get(@persistent_term_key)

      generators ->
        generators
    end
  end

  defp discover do
    for {app, _description, _vsn} <- Application.loaded_applications(),
        {:ok, modules} <- [:application.get_key(app, :modules)],
        module <- modules,
        generator_module?(module) do
      module
    end
  end

  defp generator_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__maestro_generators__, 0)
  end
end
