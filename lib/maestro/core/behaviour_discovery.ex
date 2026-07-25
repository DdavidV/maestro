defmodule Maestro.Core.BehaviourDiscovery do
  @moduledoc """
  Finds every currently-loaded module that implements a given behaviour.
  """

  @doc """
  Every loaded module whose `@behaviour` attributes include `behaviour`.
  """
  @spec modules_implementing(module) :: [module]
  def modules_implementing(behaviour) when is_atom(behaviour) do
    # Each loaded application's .app resource file lists every module it
    # compiled, whether or not that module has actually been loaded into
    # the VM yet (Elixir/Erlang load modules on demand, not eagerly)
    # Code.ensure_loaded?/1 forces the load so module_info/1 below can
    # inspect it. Using :code.all_loaded/0 instead would silently miss any
    # module nothing else in the app happens to reference yet, defeating the
    # point of "use ... is enough to register".
    for {app, _description, _vsn} <- Application.loaded_applications(),
        {:ok, modules} <- [:application.get_key(app, :modules)],
        module <- modules,
        implements?(module, behaviour) do
      module
    end
  end

  defp implements?(module, behaviour) do
    Code.ensure_loaded?(module) and
      behaviour in (module.module_info(:attributes)[:behaviour] || [])
  end
end
