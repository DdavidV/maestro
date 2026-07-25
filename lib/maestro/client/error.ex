defmodule Maestro.Client.Error do
  @moduledoc """
  A structured dispatch failure, everything that can go wrong getting a
  step's rendered template turned into a response, before there's any
  actual response to run assertions against. Distinct from
  `Maestro.Assert.Reason`: an assertion mismatch compares an expected
  value to an actual one, but a dispatch failure means that comparison
  never happened at all, so there's no `expected`/`actual` pair to report,
  only what went wrong and where in the dispatch pipeline it happened.

  `stage` says which part of `Maestro.Core.Runner.Step`'s dispatch
  pipeline failed: `:interpolation` (a `{{placeholder}}` in the step's
  template/options didn't resolve, `reason: :payload_render_failed` or
  `:options_render_failed`), `:client_lookup` (`step.client` isn't a
  registered `Maestro.Client`, `reason: :client_not_found`), or `:send`
  (the client module's own `init/2` or `send/2` returned `{:error, _}`,
  `reason: :send_failed`, or raised, `reason: :client_raised` `init/2`
  and `send/2` run back-to-back as one `Maestro.Client.call/2` step, so a
  failure in either lands here rather than as a separately distinguishable
  stage). `details` carries whatever the underlying failure actually was
  the raw `{:error, term}` payload for a normal failure, or
  `Exception.message/1` for a rescued crash.
  """

  @type stage :: :interpolation | :client_lookup | :send

  @type t :: %__MODULE__{
          stage: stage,
          reason: atom,
          details: term
        }

  @enforce_keys [:stage, :reason]
  defstruct stage: nil, reason: nil, details: nil

  @doc "Builds a `t:t/0`."
  @spec new(stage, reason :: atom, details :: term) :: t()
  def new(stage, reason, details \\ nil) when is_atom(reason) and not is_nil(reason) do
    %__MODULE__{stage: stage, reason: reason, details: details}
  end
end
