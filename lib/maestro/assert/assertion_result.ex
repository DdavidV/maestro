defmodule Maestro.Assert.AssertionResult do
  @moduledoc """
  The outcome of running one `t:Maestro.assertion/0` against a step's
  response, as produced by `Maestro.Core.AssertRunner.run_assertions/3`.

  `reasons` is always `[]` on `status: :ok`, and a non-empty
  `[Maestro.Assert.Reason.t()]` on `status: :error` the matcher's own
  `{:error, reasons}` payload, passed through unchanged,
  or a single synthetic `Reason.t()` (`reason: :matcher_not_found`)
  if `assertion.matcher` didn't resolve to a registered matcher at all.
  """

  @type t :: %__MODULE__{
          status: :ok | :error,
          assertion: Maestro.assertion(),
          actual: term,
          reasons: [Maestro.Assert.Reason.t()]
        }

  @derive Jason.Encoder
  @enforce_keys [:status, :assertion, :actual]
  defstruct status: nil, assertion: nil, actual: nil, reasons: []
end
