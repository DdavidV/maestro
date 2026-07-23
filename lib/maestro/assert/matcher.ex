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
  fields merged with accumulated `save` state) `Maestro.Core.StepRunner`
  already builds for rendering the step's own template. The assertion is
  **not** pre-interpolated for you: `properties`/`expected` is matcher-owned
  and opaque, the same way a template's `payload`/`options` are opaque to
  everything except the client that renders/sends them, so each matcher
  decides what inside its own fields needs templating and when. The
  built-in `Maestro.Matchers.JsonMatch` interpolates `expected` but
  not `path`, for example.
  """

  @callback name() :: String.t()
  @callback match(
              assertion :: Maestro.assertion(),
              actual :: term,
              context :: Maestro.Core.Interpolation.context()
            ) ::
              :ok | {:error, term}

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
