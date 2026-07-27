defmodule Maestro.Core.Interpolation do
  @moduledoc """
  Renders `{{placeholder}}` references in a template.

  A string containing nothing but one placeholder (`"{{qty}}"`) resolves to
  the context value's raw, original type so a dataset field like
  `"qty" => 1` stays an integer rather than becoming the string `"1"`. A
  placeholder embedded inside a larger string (`"Bearer {{auth_token}}"`)
  always stringifies and concatenates, since a mixed string has nowhere
  else to put a non-string type. Maps and lists are walked recursively
  every other value passes through unchanged.

  A placeholder referencing a key absent from `context` is an error.

  ## `$generated` values

  A single-key map `%{"$generated" => directive}` is recognized before the
  generic map-walk and resolved to a fresh value on every `render/2` call,
  e.g. once per row for a rows-dataset, since this runs at the same point
  `{{placeholder}}` substitution already does deliberately not once at
  suite-resolve time, so a rows-dataset's every row gets its own freshly
  generated value rather than one value reused across the whole run.
  `directive` is one of:

    * a bare string name (`"today"`) sugar for the named form below with
      no args.
    * `%{"name" => name, "args" => args}` looks up `name` in
      `Maestro.Generator.Registry` and calls that module's `generate/3`.
    * `%{"module" => mod, "function" => fun, "args" => args}` calls that
      MF directly via `Maestro.Core.SafeMFA.apply/3`, bypassing the
      registry entirely.

  Either way, `args` (default `[]`) is itself rendered against `context`
  first, so `{{placeholder}}` references inside `args` resolve before the
  generator/MFA call, same as `$mfa`'s own documented behavior. The
  resulting value is spliced in directly, not re-walked for further
  `$generated`/`{{placeholder}}` markers.
  """

  alias Maestro.Core.SafeMFA
  alias Maestro.Generator.Registry, as: GeneratorRegistry

  @type context :: %{String.t() => term}
  @type error ::
          {:missing_interpolation_key, String.t()}
          | {:generator_not_found, String.t()}
          | {:generator_failed, String.t(), term}
          | {:invalid_generated_directive, term}

  @placeholder ~r/\{\{(\w+)\}\}/
  @whole_placeholder ~r/^\{\{(\w+)\}\}$/

  @doc """
  Renders every `{{placeholder}}` in `value` against `context`, recursively.
  """
  @spec render(term, context) :: {:ok, term} | {:error, error}
  def render(%{"$generated" => directive} = m, context) when map_size(m) == 1 do
    resolve_generated(directive, context)
  end

  def render(value, context) when is_binary(value) do
    case Regex.run(@whole_placeholder, value) do
      [_, key] -> fetch(context, key)
      nil -> render_mixed(value, context)
    end
  end

  def render(value, context) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, acc} ->
      case render(item, context) do
        {:ok, rendered} -> {:cont, {:ok, Map.put(acc, key, rendered)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  def render(value, context) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case render(item, context) do
        {:ok, rendered} -> {:cont, {:ok, [rendered | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  def render(value, _context), do: {:ok, value}

  defp render_mixed(string, context) do
    @placeholder
    |> Regex.scan(string)
    |> Enum.reduce_while({:ok, string}, fn [match, key], {:ok, acc} ->
      case fetch(context, key) do
        {:ok, value} -> {:cont, {:ok, String.replace(acc, match, to_string(value))}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp fetch(context, key) do
    case Map.fetch(context, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_interpolation_key, key}}
    end
  end

  defp resolve_generated(name, context) when is_binary(name) do
    resolve_generated(%{"name" => name}, context)
  end

  defp resolve_generated(%{"module" => mod_str, "function" => fun_str} = m, context)
       when is_binary(mod_str) and is_binary(fun_str) do
    with {:ok, args} <- render(Map.get(m, "args", []), context) do
      case SafeMFA.apply(mod_str, fun_str, args) do
        {:ok, _module, _function, result} -> {:ok, result}
        {:error, _reason} = error -> error
      end
    end
  end

  defp resolve_generated(%{"name" => name} = m, context) when is_binary(name) do
    with {:ok, args} <- render(Map.get(m, "args", []), context) do
      case GeneratorRegistry.fetch(name) do
        {:ok, module} -> call_generator(module, name, args, context)
        {:error, :not_found} -> {:error, {:generator_not_found, name}}
      end
    end
  end

  defp resolve_generated(directive, _context) do
    {:error, {:invalid_generated_directive, directive}}
  end

  defp call_generator(module, name, args, context) do
    case module.generate(name, args, context) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:generator_failed, name, reason}}
    end
  rescue
    exception -> {:error, {:generator_failed, name, Exception.message(exception)}}
  end
end
