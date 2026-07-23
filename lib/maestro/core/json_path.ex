defmodule Maestro.Core.JsonPath do
  @moduledoc """
  Extracts a value from a JSON-decoded (string-keyed) term using a small
  `"$.a.b.c"`-style path syntax. Shared by `Maestro.Core.StepRunner` (`save`)
  and `Maestro.Matchers.JsonMatch` (`path`) so both use identical
  syntax and failure behavior.

  A path segment steps into a map by key, or into a list by a 0-based
  index (`"$.data.0"` is the list's first element) an index segment must
  be the whole segment as plain digits, no sign.
  """

  @type reason ::
          {:missing_key, String.t()}
          | {:invalid_index, String.t()}
          | {:index_out_of_range, non_neg_integer, non_neg_integer}
          | {:not_indexable, term}
          | {:invalid_path, String.t()}

  @doc """
  Extracts the value at `path` (e.g. `"$.token"`, `"$.items.0"`) from
  `value`.

  On failure, `reason` says exactly why: `{:missing_key, key}` (a map
  didn't have that key), `{:invalid_index, segment}` (a list segment
  wasn't plain non-negative digits), `{:index_out_of_range, index,
  length}` (a valid index, but past the end of the list),
  `{:not_indexable, value}` (a segment remained but `value` is neither a
  map nor a list), or `{:invalid_path, path}` (`path` didn't start with
  `"$."`).
  """
  @spec extract(term, String.t()) :: {:ok, term} | {:error, reason}
  def extract(value, "$." <> rest) do
    rest |> String.split(".") |> get_in_path(value)
  end

  def extract(_value, path), do: {:error, {:invalid_path, path}}

  defp get_in_path([], value), do: {:ok, value}

  defp get_in_path([key | rest], %{} = map) do
    case Map.fetch(map, key) do
      {:ok, value} -> get_in_path(rest, value)
      :error -> {:error, {:missing_key, key}}
    end
  end

  defp get_in_path([key | rest], list) when is_list(list) do
    case parse_index(key) do
      {:ok, index} ->
        case Enum.fetch(list, index) do
          {:ok, value} -> get_in_path(rest, value)
          :error -> {:error, {:index_out_of_range, index, length(list)}}
        end

      :error ->
        {:error, {:invalid_index, key}}
    end
  end

  defp get_in_path(_keys, value), do: {:error, {:not_indexable, value}}

  defp parse_index(key) do
    case Integer.parse(key) do
      {index, ""} when index >= 0 -> {:ok, index}
      _ -> :error
    end
  end
end
