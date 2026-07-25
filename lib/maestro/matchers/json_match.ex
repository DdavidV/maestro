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

  ## Failure reporting

  A failing match returns `{:error, reasons}` where `reasons` is a
  `[Maestro.Assert.Reason.t()]` **every** mismatch found in one pass, not
  just the first (see `Maestro.Assert.Reason` for the `expected`/`actual`/
  `path` fields referenced below). Every `reason` atom this matcher can
  produce:

    * `:not_equal` scalar `expected`/`actual` differ.
    * `:object_expected` / `:list_expected` `expected`'s shape (object or
      list) doesn't match `actual`'s type. `expected` is `nil` for the
      three list-only directives (`$contains`/`$excludes`/`$length`)
      there's no single "expected value" to show, only "a list was
      required here."
    * `:expected_key_missing` a `"$expected"` key, or an ordinarily-keyed
      field, is absent from `actual`. `path` includes the missing key.
    * `:unexpected_key_present` a `"$unexpected"` key is present in
      `actual`. `actual` is that key's value from the response `path`
      already locates which key, so `actual` doesn't repeat it.
    * `:invalid_closed_object_directive` `"$_"` was paired with something
      other than `"$unexpected"`.
    * `:unexpected_extra_keys` a closed object (`"$_" => "$unexpected"`)
      has keys beyond those named. `expected`/`actual` are the sorted
      allowed-key list and sorted actual-key list, respectively.
    * `:length_mismatch` an ordered list's length doesn't match
      `expected`'s (bare-array matching, not the `$length` directive).
      Reported alongside any paired-index element mismatches, not instead
      of them.
    * `:invalid_unexpected_position` a `"$unexpected"` element appears
      somewhere other than the last position of an ordered list.
    * `:contains_item_not_found` a `$contains` item has no match anywhere
      in `actual`. `expected` is that item, `actual` is the whole list.
    * `:excluded_item_found` a `$excludes` item matched an element of
      `actual`. `expected` is that item, `actual` is the matching element.
    * `:length_not_equal` / `:length_not_greater_than` /
      `:length_not_less_than` / `:length_not_between` a `$length` spec
      wasn't satisfied. `expected` is the bound(s) from the spec, `actual`
      is `actual`'s real length.
    * `:invalid_length_directive` a `$length` spec was malformed (not an
      integer or a recognized `$gt`/`$lt`/`$between` wrapper).
    * `:regex_no_match` a `$regex` pattern compiled fine but didn't match.
    * `:invalid_regex` a `$regex` pattern failed to compile, or was
      applied to a non-string `actual`, or wasn't itself a string.
    * `:mfa_check_failed` a `$mfa` call resolved and ran, but returned
      `false` or `{:error, reason}`. `expected` is `{module, function}`
      (the resolved atoms, not the original strings).
    * `:invalid_mfa_result` a `$mfa` call returned something other than
      `true`/`:ok`/`false`/`{:error, _}`.
    * `:mfa_error` `Maestro.Core.SafeMFA.apply/3` itself failed module/
      function resolution, or the call raised (see its `t:reason/0`  for
      the exact `actual` shapes: `:mfa_module_not_found`,
      `:mfa_function_not_found`, `:mfa_not_exported`, `:mfa_raised`).
    * `:invalid_mfa_directive` `$mfa`'s payload wasn't
      `%{"module" => ..., "function" => ...}`.
    * `:interpolation_failed` a `{{placeholder}}` in `expected` didn't
      resolve against `context`. `expected` is the missing key name,
      `actual` is `nil` there's no response value to show when
      `expected` itself never finished rendering.
    * `:path_not_found` the assertion's own `path` didn't resolve against
      `actual` (via `Maestro.Core.JsonPath`) this one always short-
      circuits as the sole entry in `reasons`, since nothing else can be
      checked without a target. `expected` is the `path` string itself,
      `actual` is `nil` there's no resolved value to show when the path
      never resolved to one.
  """

  use Maestro.Assert.Matcher, name: "json_match"

  alias Maestro.Assert.Reason
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
    root_path = Map.get(assertion, :path)

    case select_target(assertion, actual, root_path) do
      {:ok, target} ->
        case Interpolation.render(assertion.expected, context) do
          {:ok, expected} ->
            case match_value(expected, target, root_path) do
              [] -> :ok
              reasons -> {:error, reasons}
            end

          {:error, {:missing_interpolation_key, key}} ->
            {:error, [Reason.new(:interpolation_failed, key, nil, root_path)]}
        end

      {:error, reason} ->
        {:error, [reason]}
    end
  end

  defp select_target(%{path: path}, actual, _root_path) do
    case JsonPath.extract(actual, path) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, Reason.new(:path_not_found, path, nil)}
    end
  end

  defp select_target(_assertion, actual, _root_path), do: {:ok, actual}

  # Every match_* clause returns [Reason.t()] -- [] means "matched".

  defp match_value(%{@contains_key => wanted} = m, actual, path) when map_size(m) == 1 do
    match_contains(wanted, actual, path)
  end

  defp match_value(%{@excludes_key => excluded} = m, actual, path) when map_size(m) == 1 do
    match_excludes(excluded, actual, path)
  end

  defp match_value(%{@length_key => spec} = m, actual, path) when map_size(m) == 1 do
    match_length(spec, actual, path)
  end

  defp match_value(%{@regex_key => pattern} = m, actual, path) when map_size(m) == 1 do
    match_regex(pattern, actual, path)
  end

  defp match_value(%{@mfa_key => mfa} = m, actual, path) when map_size(m) == 1 do
    match_mfa(mfa, actual, path)
  end

  defp match_value(expected, actual, path) when is_map(expected) and is_map(actual) do
    match_object(expected, actual, path)
  end

  defp match_value(expected, actual, path) when is_map(expected) do
    [Reason.new(:object_expected, expected, actual, path)]
  end

  defp match_value(expected, actual, path) when is_list(expected) and is_list(actual) do
    match_ordered(expected, actual, path)
  end

  defp match_value(expected, actual, path) when is_list(expected) do
    [Reason.new(:list_expected, expected, actual, path)]
  end

  defp match_value(expected, actual, path) do
    if expected == actual, do: [], else: [Reason.new(:not_equal, expected, actual, path)]
  end

  defp match_object(expected, actual, path) do
    case split_closed(expected, actual, path) do
      {:ok, closed?, fields} ->
        field_reasons = match_fields(fields, actual, path)
        closed_reasons = if closed?, do: check_closed(fields, actual, path), else: []
        field_reasons ++ closed_reasons

      {:error, reason} ->
        [reason]
    end
  end

  defp split_closed(expected, _actual, path) do
    case Map.fetch(expected, @closed_key) do
      {:ok, @unexpected} -> {:ok, true, Map.delete(expected, @closed_key)}
      {:ok, other} -> {:error, Reason.new(:invalid_closed_object_directive, other, nil, path)}
      :error -> {:ok, false, expected}
    end
  end

  defp match_fields(fields, actual, path) do
    Enum.flat_map(fields, fn {key, value} -> match_field(key, value, actual, path) end)
  end

  defp match_field(key, @unexpected, actual, path) do
    case Map.fetch(actual, key) do
      {:ok, value} ->
        [Reason.new(:unexpected_key_present, @unexpected, value, field_path(path, key))]

      :error ->
        []
    end
  end

  defp match_field(key, @expected, actual, path) do
    if Map.has_key?(actual, key) do
      []
    else
      [Reason.new(:expected_key_missing, @expected, nil, field_path(path, key))]
    end
  end

  defp match_field(key, expected_value, actual, path) do
    case Map.fetch(actual, key) do
      {:ok, actual_value} ->
        match_value(expected_value, actual_value, field_path(path, key))

      :error ->
        [Reason.new(:expected_key_missing, expected_value, nil, field_path(path, key))]
    end
  end

  defp check_closed(fields, actual, path) do
    case Map.keys(actual) -- Map.keys(fields) do
      [] ->
        []

      _extra ->
        [
          Reason.new(
            :unexpected_extra_keys,
            Enum.sort(Map.keys(fields)),
            Enum.sort(Map.keys(actual)),
            path
          )
        ]
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
  defp match_ordered(expected, actual, path) do
    case Enum.find_index(expected, &(&1 == @unexpected)) do
      nil ->
        match_ordered_exact(expected, actual, path)

      index when index == length(expected) - 1 ->
        match_ordered_closed(Enum.slice(expected, 0, index), actual, path)

      index ->
        [Reason.new(:invalid_unexpected_position, index, length(expected), path)]
    end
  end

  defp match_ordered_exact(expected, actual, path) when length(expected) != length(actual) do
    [Reason.new(:length_mismatch, length(expected), length(actual), path)] ++
      match_ordered_pairs(expected, actual, path)
  end

  defp match_ordered_exact(expected, actual, path),
    do: match_ordered_pairs(expected, actual, path)

  defp match_ordered_closed(required, actual, path) when length(required) != length(actual) do
    [Reason.new(:length_mismatch, length(required), length(actual), path)] ++
      match_ordered_pairs(required, actual, path)
  end

  defp match_ordered_closed(required, actual, path),
    do: match_ordered_pairs(required, actual, path)

  defp match_ordered_pairs(expected, actual, path) do
    expected
    |> Enum.zip(actual)
    |> Enum.with_index()
    |> Enum.flat_map(fn {{exp, act}, index} ->
      match_ordered_element(exp, act, index_path(path, index))
    end)
  end

  defp match_ordered_element(@expected, _actual, _path), do: []
  defp match_ordered_element(expected, actual, path), do: match_value(expected, actual, path)

  defp match_contains(wanted, actual, path) when is_list(wanted) and is_list(actual) do
    {_remaining, reasons} =
      Enum.reduce(wanted, {actual, []}, fn item, {remaining, reasons} ->
        case take_first_match(item, remaining) do
          {:ok, rest} ->
            {rest, reasons}

          :error ->
            {remaining, reasons ++ [Reason.new(:contains_item_not_found, item, actual, path)]}
        end
      end)

    reasons
  end

  defp match_contains(_wanted, actual, path) do
    [Reason.new(:list_expected, nil, actual, path)]
  end

  defp take_first_match(item, remaining) do
    case Enum.split_while(remaining, &(match_value(item, &1, nil) != [])) do
      {_before, []} -> :error
      {before, [_match | rest]} -> {:ok, before ++ rest}
    end
  end

  defp match_excludes(excluded, actual, path) when is_list(excluded) and is_list(actual) do
    Enum.flat_map(excluded, fn item ->
      case Enum.find(actual, &(match_value(item, &1, nil) == [])) do
        nil -> []
        found -> [Reason.new(:excluded_item_found, item, found, path)]
      end
    end)
  end

  defp match_excludes(_excluded, actual, path) do
    [Reason.new(:list_expected, nil, actual, path)]
  end

  defp match_length(spec, actual, path) when is_list(actual) do
    match_length_spec(spec, length(actual), path)
  end

  defp match_length(_spec, actual, path) do
    [Reason.new(:list_expected, nil, actual, path)]
  end

  defp match_length_spec(expected_length, actual_length, path) when is_integer(expected_length) do
    if actual_length == expected_length,
      do: [],
      else: [Reason.new(:length_not_equal, expected_length, actual_length, path)]
  end

  defp match_length_spec(%{@gt_key => min} = m, actual_length, path) when map_size(m) == 1 do
    if actual_length > min,
      do: [],
      else: [Reason.new(:length_not_greater_than, min, actual_length, path)]
  end

  defp match_length_spec(%{@lt_key => max} = m, actual_length, path) when map_size(m) == 1 do
    if actual_length < max,
      do: [],
      else: [Reason.new(:length_not_less_than, max, actual_length, path)]
  end

  defp match_length_spec(%{@between_key => [min, max]} = m, actual_length, path)
       when map_size(m) == 1 do
    if actual_length >= min and actual_length <= max,
      do: [],
      else: [Reason.new(:length_not_between, [min, max], actual_length, path)]
  end

  defp match_length_spec(spec, _actual_length, path) do
    [Reason.new(:invalid_length_directive, spec, nil, path)]
  end

  defp match_regex(pattern, actual, path) when is_binary(pattern) and is_binary(actual) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        if Regex.match?(regex, actual),
          do: [],
          else: [Reason.new(:regex_no_match, pattern, actual, path)]

      {:error, reason} ->
        [Reason.new(:invalid_regex, pattern, reason, path)]
    end
  end

  defp match_regex(pattern, actual, path) when is_binary(pattern) do
    [Reason.new(:invalid_regex, pattern, actual, path)]
  end

  defp match_regex(pattern, actual, path), do: [Reason.new(:invalid_regex, pattern, actual, path)]

  defp match_mfa(%{"module" => mod_str, "function" => fun_str} = mfa, actual, path)
       when is_binary(mod_str) and is_binary(fun_str) do
    args = Map.get(mfa, "args", [])

    case SafeMFA.apply(mod_str, fun_str, [actual | args]) do
      {:ok, _module, _function, true} ->
        []

      {:ok, _module, _function, :ok} ->
        []

      {:ok, module, function, false} ->
        [Reason.new(:mfa_check_failed, {module, function}, actual, path)]

      {:ok, module, function, {:error, reason}} ->
        [Reason.new(:mfa_check_failed, {module, function}, reason, path)]

      {:ok, _module, _function, other} ->
        [Reason.new(:invalid_mfa_result, mfa, other, path)]

      {:error, reason} ->
        [Reason.new(:mfa_error, mfa, reason, path)]
    end
  end

  defp match_mfa(mfa, actual, path), do: [Reason.new(:invalid_mfa_directive, mfa, actual, path)]

  defp field_path(nil, key), do: ".#{key}"
  defp field_path(path, key), do: "#{path}.#{key}"

  defp index_path(nil, index), do: "[#{index}]"
  defp index_path(path, index), do: "#{path}[#{index}]"
end
