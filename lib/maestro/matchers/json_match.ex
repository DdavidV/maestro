defmodule Maestro.Matchers.JsonMatch do
  @moduledoc """
  The built-in KATT-inspired structural JSON matcher, registered as
  `"json_match"`.

  `expected` (see `t:Maestro.assertion/0`) is rendered through
  `Maestro.Core.Interpolation.render/2` against the step's dataset/saved
  state once, up front, before any matching happens so `{{dataset_field}}`
  style templating "just works" anywhere in the tree,
  including inside the directives below. `path` (optional) selects a
  sub-value of the step's response to check via `Maestro.Core.JsonPath`;
  if omitted, the whole response is checked.

  ## Directives

  All bracketed directives below are single-key wrapper objects
  (`%{"$word" => payload}`) recognized before the generic object-match
  clause, and (since matching is one uniformly recursive function) they
  nest and recurse freely, e.g. `%{"$contains" => [%{"id" => "$expected"}]}`.

    * `"$expected"` (value, inside an object) the key must be present
      its value isn't checked.
    * `"$unexpected"` (value, inside an object) the key must be **absent**.
    * `"$_" => "$unexpected"` (key/value pair, inside an object) closed-
      object directive: `actual` must have no keys beyond those named in
      `expected` (excluding `$_` itself). Any other value paired with `$_`
      is a hard error, not silently ignored.
    * `%{"$contains" => [...]}` (value, in place of a bare array)
      unordered subset/membership check: every wanted item must have a
      matching element somewhere in `actual`, extra elements in `actual`
      are fine. Matched **greedily** (consume-once, first-fit, not full
      bipartite matching).
    * `%{"$excludes" => [...]}` (value, in place of a bare array) the
      negative counterpart to `$contains`: none of the listed items may
      match any element of `actual`. Simpler than `$contains` no
      consume-once/greedy concerns apply, since every excluded item is
      checked against the *whole* list independently.
    * `%{"$length" => spec}` (value, `actual` must be a list) checks the
      list's length without checking its contents. `spec` is one of a bare
      integer (`%{"$length" => 5}`, exact length), `%{"$gt" => n}` (strictly
      greater than `n`), `%{"$lt" => n}` (strictly less than `n`), or
      `%{"$between" => [min, max]}` (inclusive on both ends). Like every
      other single-key-wrapper directive, `$length` can't be combined with
      `$contains`/`$excludes` *in the same wrapper* (a map with more than
      one key falls through to a literal object match instead, which would
      then fail against a list `actual`) checking both length and
      contents of the same list needs two separate `assert` entries with
      the same `path`.
    * bare `[...]` (value) ordered, exact-length, index-by-index match.
      This is the default. `"$expected"` may appear as an element at any
      index (a positional wildcard: there must be an element there, its
      value isn't checked). `"$unexpected"` may appear only as the
      **last** element, meaning "the list ends here" `actual` must have
      exactly as many elements as come before it, and nothing is checked
      past that length; `"$unexpected"` anywhere else is a hard error, a
      position can't simultaneously not exist and have positions after it
      that must. Both are ordered-list-only; `$contains` ignores them.
    * `%{"$regex" => pattern}` (value) `actual` must be a string matching
      `Regex.compile(pattern)`.
    * `%{"$mfa" => %{"module" => m, "function" => f, "args" => a}}` (value)
      runs `apply(module, function, [actual | args])` as a check. Accepts
      `true`/`:ok` (pass), `false` (fail), `{:error, reason}` (fail with
      that reason), anything else is `{:invalid_mfa_result, other}`. This
      is authored-suite-file code invoking arbitrary already-loaded
      functions, module/function resolution uses
      `Module.safe_concat/1` + `String.to_existing_atom/1`, checks
      `Code.ensure_loaded?/1` + `function_exported?/3` before calling, and
      wraps the call in `rescue`.

  A directive key present alongside sibling keys (e.g.
  `%{"$contains" => [...], "other" => 1}`) is **not** treated as a
  directive it falls through to a literal object match, where an author
  wanting that would need `actual` to literally have a `"$contains"` key
  too. Documented edge case, not specially handled: vanishingly unlikely to
  matter in practice.
  """

  use Maestro.Assert.Matcher, name: "json_match"

  alias Maestro.Core.Interpolation
  alias Maestro.Core.JsonPath
  alias Maestro.Core.SafeMFA

  @unexpected "$unexpected"
  @expected "$expected"
  @closed_key "$_"
  @contains_key "$contains"
  @excludes_key "$excludes"
  @length_key "$length"
  @gt_key "$gt"
  @lt_key "$lt"
  @between_key "$between"
  @regex_key "$regex"
  @mfa_key "$mfa"

  @impl true
  def match(assertion, actual, context) do
    with {:ok, target} <- select_target(assertion, actual),
         {:ok, expected} <- Interpolation.render(assertion.expected, context) do
      match_value(expected, target)
    end
  end

  defp select_target(%{path: path}, actual) do
    case JsonPath.extract(actual, path) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:path_not_found, path, reason}}
    end
  end

  defp select_target(_assertion, actual), do: {:ok, actual}

  defp match_value(%{@contains_key => wanted} = m, actual) when map_size(m) == 1 do
    match_contains(wanted, actual)
  end

  defp match_value(%{@excludes_key => excluded} = m, actual) when map_size(m) == 1 do
    match_excludes(excluded, actual)
  end

  defp match_value(%{@length_key => spec} = m, actual) when map_size(m) == 1 do
    match_length(spec, actual)
  end

  defp match_value(%{@regex_key => pattern} = m, actual) when map_size(m) == 1 do
    match_regex(pattern, actual)
  end

  defp match_value(%{@mfa_key => mfa} = m, actual) when map_size(m) == 1 do
    match_mfa(mfa, actual)
  end

  defp match_value(expected, actual) when is_map(expected) and is_map(actual) do
    match_object(expected, actual)
  end

  defp match_value(expected, actual) when is_map(expected) do
    {:error, {:type_mismatch, :object_expected, actual}}
  end

  defp match_value(expected, actual) when is_list(expected) and is_list(actual) do
    match_ordered(expected, actual)
  end

  defp match_value(expected, actual) when is_list(expected) do
    {:error, {:type_mismatch, :list_expected, actual}}
  end

  defp match_value(expected, actual) do
    if expected == actual, do: :ok, else: {:error, {:not_equal, expected, actual}}
  end

  defp match_object(expected, actual) do
    with {:ok, closed?, fields} <- split_closed(expected),
         :ok <- match_fields(fields, actual) do
      if closed?, do: check_closed(fields, actual), else: :ok
    end
  end

  defp split_closed(expected) do
    case Map.fetch(expected, @closed_key) do
      {:ok, @unexpected} -> {:ok, true, Map.delete(expected, @closed_key)}
      {:ok, other} -> {:error, {:invalid_closed_object_directive, other}}
      :error -> {:ok, false, expected}
    end
  end

  defp match_fields(fields, actual) do
    Enum.reduce_while(fields, :ok, fn {key, value}, :ok ->
      case match_field(key, value, actual) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp match_field(key, @unexpected, actual) do
    if Map.has_key?(actual, key), do: {:error, {:unexpected_key_present, key}}, else: :ok
  end

  defp match_field(key, @expected, actual) do
    if Map.has_key?(actual, key), do: :ok, else: {:error, {:expected_key_missing, key}}
  end

  defp match_field(key, expected_value, actual) do
    case Map.fetch(actual, key) do
      {:ok, actual_value} ->
        case match_value(expected_value, actual_value) do
          :ok -> :ok
          {:error, reason} -> {:error, {:field_mismatch, key, reason}}
        end

      :error ->
        {:error, {:expected_key_missing, key}}
    end
  end

  defp check_closed(fields, actual) do
    case Map.keys(actual) -- Map.keys(fields) do
      [] -> :ok
      extra -> {:error, {:unexpected_extra_keys, extra}}
    end
  end

  # A bare "$unexpected" element is only meaningful as the very last element
  # of an ordered list ("the list ends here, don't check anything beyond
  # this length") anywhere else it's ambiguous (a position can't both be
  # "must not exist" and have positions after it that "must exist"), so
  # that's a hard error rather than guessed at. "$expected" has no such
  # positional restriction: at any index it just means "there is an
  # element here, don't check its value" (a within-bounds guarantee that
  # either length check below already establishes).
  defp match_ordered(expected, actual) do
    case Enum.find_index(expected, &(&1 == @unexpected)) do
      nil ->
        match_ordered_exact(expected, actual)

      index when index == length(expected) - 1 ->
        match_ordered_closed(Enum.slice(expected, 0, index), actual)

      index ->
        {:error, {:invalid_unexpected_position, index, length(expected)}}
    end
  end

  defp match_ordered_exact(expected, actual) when length(expected) != length(actual) do
    {:error, {:length_mismatch, length(expected), length(actual)}}
  end

  defp match_ordered_exact(expected, actual), do: match_ordered_pairs(expected, actual)

  defp match_ordered_closed(required, actual) when length(required) != length(actual) do
    {:error, {:length_mismatch, length(required), length(actual)}}
  end

  defp match_ordered_closed(required, actual), do: match_ordered_pairs(required, actual)

  defp match_ordered_pairs(expected, actual) do
    expected
    |> Enum.zip(actual)
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {{exp, act}, index}, :ok ->
      case match_ordered_element(exp, act) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:index_mismatch, index, reason}}}
      end
    end)
  end

  defp match_ordered_element(@expected, _actual), do: :ok
  defp match_ordered_element(expected, actual), do: match_value(expected, actual)

  defp match_contains(wanted, actual) when is_list(wanted) and is_list(actual) do
    wanted
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, actual}, fn {item, index}, {:ok, remaining} ->
      case take_first_match(item, remaining) do
        {:ok, rest} -> {:cont, {:ok, rest}}
        :error -> {:halt, {:error, {:contains_item_not_found, index, item}}}
      end
    end)
    |> case do
      {:ok, _remaining} -> :ok
      error -> error
    end
  end

  defp match_contains(_wanted, actual), do: {:error, {:type_mismatch, :list_expected, actual}}

  defp take_first_match(item, remaining) do
    case Enum.split_while(remaining, &(match_value(item, &1) != :ok)) do
      {_before, []} -> :error
      {before, [_match | rest]} -> {:ok, before ++ rest}
    end
  end

  defp match_excludes(excluded, actual) when is_list(excluded) and is_list(actual) do
    excluded
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      case Enum.find_index(actual, &(match_value(item, &1) == :ok)) do
        nil -> {:cont, :ok}
        found_at -> {:halt, {:error, {:excluded_item_found, index, found_at, item}}}
      end
    end)
  end

  defp match_excludes(_excluded, actual), do: {:error, {:type_mismatch, :list_expected, actual}}

  defp match_length(spec, actual) when is_list(actual) do
    match_length_spec(spec, length(actual))
  end

  defp match_length(_spec, actual), do: {:error, {:type_mismatch, :list_expected, actual}}

  defp match_length_spec(expected_length, actual_length) when is_integer(expected_length) do
    if actual_length == expected_length,
      do: :ok,
      else: {:error, {:length_not_equal, expected_length, actual_length}}
  end

  defp match_length_spec(%{@gt_key => min} = m, actual_length) when map_size(m) == 1 do
    if actual_length > min,
      do: :ok,
      else: {:error, {:length_not_greater_than, min, actual_length}}
  end

  defp match_length_spec(%{@lt_key => max} = m, actual_length) when map_size(m) == 1 do
    if actual_length < max,
      do: :ok,
      else: {:error, {:length_not_less_than, max, actual_length}}
  end

  defp match_length_spec(%{@between_key => [min, max]} = m, actual_length)
       when map_size(m) == 1 do
    if actual_length >= min and actual_length <= max,
      do: :ok,
      else: {:error, {:length_not_between, min, max, actual_length}}
  end

  defp match_length_spec(spec, _actual_length), do: {:error, {:invalid_length_directive, spec}}

  defp match_regex(pattern, actual) when is_binary(pattern) and is_binary(actual) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        if Regex.match?(regex, actual),
          do: :ok,
          else: {:error, {:regex_no_match, pattern, actual}}

      {:error, reason} ->
        {:error, {:invalid_regex, pattern, reason}}
    end
  end

  defp match_regex(pattern, actual) when is_binary(pattern) do
    {:error, {:regex_requires_string, pattern, actual}}
  end

  defp match_regex(pattern, _actual), do: {:error, {:invalid_regex_directive, pattern}}

  defp match_mfa(%{"module" => mod_str, "function" => fun_str} = mfa, actual)
       when is_binary(mod_str) and is_binary(fun_str) do
    args = Map.get(mfa, "args", [])

    case SafeMFA.apply(mod_str, fun_str, [actual | args]) do
      {:ok, _module, _function, true} ->
        :ok

      {:ok, _module, _function, :ok} ->
        :ok

      {:ok, module, function, false} ->
        {:error, {:mfa_check_failed, module, function}}

      {:ok, module, function, {:error, reason}} ->
        {:error, {:mfa_check_failed, module, function, reason}}

      {:ok, _module, _function, other} ->
        {:error, {:invalid_mfa_result, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp match_mfa(mfa, _actual), do: {:error, {:invalid_mfa_directive, mfa}}
end
