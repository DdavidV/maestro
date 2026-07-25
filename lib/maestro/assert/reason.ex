defmodule Maestro.Assert.Reason do
  @moduledoc """
  One structured entry in the list a `Maestro.Assert.Matcher.match/3` call
  returns on failure (`{:error, [Reason.t()]}`).

  `reason` is a short, machine-readable atom naming what kind of mismatch
  this is (`:not_equal`, `:length_mismatch`, `:expected_key_missing`, ...).
  `expected`/`actual` are the specific values that differed for *this*
  entry for a mismatch nested inside a larger structure (an object
  field, a list index, ...) these are the nested sub-values, not
  necessarily the assertion's whole `expected`/the whole response, with
  `path` saying where (e.g. `"$.items[2].id"`, `nil` when there's nothing
  to descend into).

  A single `match/3` call can return several of these a matcher that
  finds multiple independent problems reports all of them in one list,
  rather than only the first one found.
  """

  @type t :: %__MODULE__{
          reason: atom,
          expected: term,
          actual: term,
          path: String.t() | nil
        }

  @enforce_keys [:reason]
  defstruct reason: nil, expected: nil, actual: nil, path: nil

  @doc "Builds a `t:t/0`."
  @spec new(reason :: atom, expected :: term, actual :: term, path :: String.t() | nil) :: t()
  def new(reason, expected \\ nil, actual \\ nil, path \\ nil)
      when is_atom(reason) and not is_nil(reason) do
    %__MODULE__{reason: reason, expected: expected, actual: actual, path: path}
  end
end
