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
  """

  @type context :: %{String.t() => term}
  @type error :: {:missing_interpolation_key, String.t()}

  @placeholder ~r/\{\{(\w+)\}\}/
  @whole_placeholder ~r/^\{\{(\w+)\}\}$/

  @doc """
  Renders every `{{placeholder}}` in `value` against `context`, recursively.
  """
  @spec render(term, context) :: {:ok, term} | {:error, error}
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
end
