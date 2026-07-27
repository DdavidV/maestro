defmodule Maestro.Core.RegistryCollisions do
  @moduledoc """
  Shared collision check for the name-to-module discovery registries.
  Each discovers modules by scanning every loaded application, so which
  module "wins" a name collision depends on
  `Application.loaded_applications()` traversal order, not something
  callers control or should rely on logging a warning instead of picking
  a winner silently at least makes the ambiguity visible.
  """

  require Logger

  @doc """
  Logs a warning for every `name` that appears more than once in `entries`
  with a different module, naming every colliding module. The same module
  appearing twice under the same name (e.g. discovered from two application
  manifests) is not a collision.
  """
  @spec warn_on_collisions(String.t(), [{String.t(), module}]) :: :ok
  def warn_on_collisions(registry_label, entries) when is_binary(registry_label) do
    entries
    |> Enum.group_by(fn {name, _module} -> name end, fn {_name, module} -> module end)
    |> Enum.each(fn {name, modules} ->
      case Enum.uniq(modules) do
        [_single] ->
          :ok

        modules ->
          Logger.warning(
            "#{registry_label}: #{inspect(name)} is registered by more than one module " <>
              "(#{Enum.map_join(modules, ", ", &inspect/1)}) only one will be used, and which " <>
              "one is not guaranteed to stay stable across runs. Rename one of them."
          )
      end
    end)
  end
end
