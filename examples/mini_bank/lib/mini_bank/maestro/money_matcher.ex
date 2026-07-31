defmodule MiniBank.Maestro.MoneyEquals do
  @moduledoc """
  Compares a monetary amount, always represented as an integer (never a
  float, avoiding float-rounding pitfalls entirely), registered as
  `"money_equals"`.

  ```json
  { "matcher": "money_equals", "path": "$.result.balance", "expected": 12500 }
  ```

  `expected` is interpolated (`{{placeholder}}`-aware) via
  `Maestro.Core.Interpolation.render/2`, same as `json_match` does for its
  own `expected`. `path` (optional, same `"$.a.b"` syntax `json_match`/
  `save` use, via `Maestro.Core.JsonPath`) selects the value to check out
  of `actual`; omitted, the whole `actual` value itself must already be an
  integer.

  An optional matcher-specific `tolerance` field (default `0`) allows an
  inexact check: passes if `abs(actual_amount - expected_amount) <=
  tolerance`. Not pre-interpolated (matcher-specific fields never are).

  ```json
  { "matcher": "money_equals", "path": "$.row.balance", "expected": 10000, "tolerance": 5 }
  ```

  ## Failure reasons

    * `:not_an_integer` - `expected` (after interpolation) or the selected
      `actual` value isn't an integer.
    * `:amount_mismatch` - both sides are integers, but
      `abs(actual - expected) > tolerance`.
    * `:path_not_found` - `path` was given but didn't resolve against
      `actual` (mirrors `json_match`'s own reason of the same name).
    * `:interpolation_failed` - a `{{placeholder}}` in `expected` didn't
      resolve (mirrors `json_match`'s own reason of the same name).
  """
  use Maestro.Assert.Matcher, name: "money_equals"

  alias Maestro.Assert.Reason
  alias Maestro.Core.Interpolation
  alias Maestro.Core.JsonPath

  @impl true
  def match(assertion, actual, context) do
    tolerance = Map.get(assertion, "tolerance", 0)
    path = Map.get(assertion, :path)

    with {:ok, target} <- select_target(actual, path),
         {:ok, expected} <- Interpolation.render(assertion.expected, context) do
      compare(expected, target, tolerance, path)
    else
      {:error, {:missing_interpolation_key, key}} ->
        {:error, [Reason.new(:interpolation_failed, key, nil, path)]}

      {:error, :path_not_found} ->
        {:error, [Reason.new(:path_not_found, path, nil, path)]}
    end
  end

  defp select_target(actual, nil), do: {:ok, actual}

  defp select_target(actual, path) do
    case JsonPath.extract(actual, path) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, :path_not_found}
    end
  end

  defp compare(expected, actual, tolerance, path)
       when is_integer(expected) and is_integer(actual) and is_integer(tolerance) do
    if abs(actual - expected) <= tolerance do
      :ok
    else
      {:error, [Reason.new(:amount_mismatch, expected, actual, path)]}
    end
  end

  defp compare(expected, actual, _tolerance, path) do
    reasons =
      [
        if(not is_integer(expected), do: Reason.new(:not_an_integer, expected, nil, path)),
        if(not is_integer(actual), do: Reason.new(:not_an_integer, nil, actual, path))
      ]
      |> Enum.reject(&is_nil/1)

    {:error, reasons}
  end
end
