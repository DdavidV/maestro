defmodule Maestro.Generator do
  @moduledoc """
  Lets one module define several named dataset value generators, each
  produces a value at render time for a `{"$generated": "name"}` (or
  `{"$generated": {"name": "name", "args": [...]}}`) marker inside a
  dataset's `data`/`rows` bag.

  ```elixir
  defmodule MyGenerators do
    use Maestro.Generator

    generated_data "today", _args, _context do
      {:ok, Date.utc_today() |> Date.to_iso8601()}
    end

    generated_data "env_var", [var_name], _context do
      case System.fetch_env(var_name) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, {:env_var_not_set, var_name}}
      end
    end
  end
  ```

  `use Maestro.Generator` is enough to be discovered (see
  `Maestro.Generator.Registry`), no explicit registration list each
  `generated_data` block registers its own name independently, so a
  module can group as many related generators as makes sense.

  `args` (already interpolated against `context` `{{placeholder}}`
  references inside them are already resolved, same as
  `Maestro.Matchers.JsonMatch`'s `$mfa` directive) and `context` (dataset
  fields merged with accumulated `save` state, the same context
  `Maestro.Core.Interpolation.render/2` already threads through) are named
  block parameters, pattern-matchable in the head like a normal function.
  A block returns `{:ok, value}` (spliced into the dataset tree in place
  of the marker) or `{:error, reason}` a raise is also caught and
  reported the same way, so a broken generator can't crash a run.

  Each `generated_data` block registers exactly one name each name must
  be unique within a module: reusing a name in the same module is a
  compile error (see `__before_compile__/1`), not a silent shadow, since
  a second same-named clause would otherwise be unreachable dead code. A
  generator needing multiple argument shapes (e.g. a zero-arg form and an
  offset-arg form) branches with a normal `case`/pattern-match inside one
  block's body, the same way any other Elixir function would, rather than
  relying on several same-named blocks to behave like multi-clause
  function heads.

  A name registered by *two different modules* is a separate, looser
  concern handled by `Maestro.Generator.Registry` at discovery time
  (a warning, not a compile error, since which modules get loaded is a
  runtime/application concern, not something a single module's own
  compilation can see).
  """

  defmacro __using__(_opts) do
    quote do
      @maestro_generators []
      @before_compile Maestro.Generator

      import Maestro.Generator, only: [generated_data: 4]
    end
  end

  @doc """
  Defines one named generator inside a `use Maestro.Generator` module.

  `args_pattern`/`context_pattern` are ordinary function-head patterns
  (matched against `generate/3`'s own `args`/`context` at dispatch time).
  """
  defmacro generated_data(name, args_pattern, context_pattern, do: body) do
    function_name = generated_function_name(name)

    quote do
      @maestro_generators [{unquote(name), unquote(function_name)} | @maestro_generators]

      defp unquote(function_name)(unquote(args_pattern), unquote(context_pattern)) do
        unquote(body)
      end
    end
  end

  defmacro __before_compile__(env) do
    generators = Module.get_attribute(env.module, :maestro_generators)

    case duplicate_names(generators) do
      [] ->
        :ok

      duplicates ->
        raise CompileError,
          file: env.file,
          line: env.line,
          description:
            "#{inspect(env.module)} registers the same generated_data name more than once: " <>
              Enum.map_join(duplicates, ", ", &inspect/1)
    end

    dispatch_clauses =
      for {name, function_name} <- generators do
        quote do
          def generate(unquote(name), args, context) do
            unquote(function_name)(args, context)
          end
        end
      end

    quote do
      @doc false
      def __maestro_generators__, do: @maestro_generators

      unquote(dispatch_clauses)

      @doc false
      def generate(_name, _args, _context), do: {:error, :not_found}
    end
  end

  defp generated_function_name(name) do
    :"__maestro_generated_#{Base.encode16(:erlang.md5(name), case: :lower)}"
  end

  defp duplicate_names(generators) do
    generators
    |> Enum.map(fn {name, _function} -> name end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> name end)
  end
end
