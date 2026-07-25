defmodule Maestro.Assert.Matcher do
  @moduledoc """
  Behaviour for a Maestro assertion matcher: something that checks an
  `t:Maestro.assertion/0` entry against a step's response.

  `use Maestro.Assert.Matcher, name: "json_match"` is enough to register a
  module (see `Maestro.Assert.Registry` for how modules implementing this
  behaviour are discovered).

  Unlike `Maestro.Client`, there is no one-time setup callback a matcher
  is expected to be static code, not something that needs memoized state.

  `match/3` receives the whole atomized `t:Maestro.assertion/0` entry
  (including `:matcher` itself, which a matcher can just ignore), the
  step's `actual` response, and the same interpolation `context` (dataset
  fields merged with accumulated `save` state) `Maestro.Core.Runner.Step`
  already builds for rendering the step's own template. The assertion is
  **not** pre-interpolated for you: `properties`/`expected` is matcher-owned
  and opaque, the same way a template's `payload`/`options` are opaque to
  everything except the client that renders/sends them, so each matcher
  decides what inside its own fields needs templating and when. The
  built-in `Maestro.Matchers.JsonMatch` interpolates `expected` but
  not `path`, for example.

  `match/3` returns bare `:ok` on a pass (nothing to report) or
  `{:error, reasons}` on a fail, where `reasons` is a non-empty list of
  `Maestro.Assert.Reason.t()`, one entry per distinct problem found. A
  matcher that only ever finds at most one problem per call can just
  return a single-element list. A matcher that can find several
  independent problems in one pass (e.g. `Maestro.Matchers.JsonMatch`
  checking every field of an object) is expected to report all of them,
  not just the first. This keeps every matcher's failure output in a
  shared, structured shape that a generic consumer (e.g. a report) can
  render without knowing that matcher's internals.
  """

  @callback name() :: String.t()
  @callback match(
              assertion :: Maestro.assertion(),
              actual :: term,
              context :: Maestro.Core.Interpolation.context()
            ) ::
              :ok | {:error, [Maestro.Assert.Reason.t()]}

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)

    quote do
      @behaviour Maestro.Assert.Matcher
      @maestro_matcher_name unquote(name)
      @impl true
      def name, do: @maestro_matcher_name
    end
  end
end
