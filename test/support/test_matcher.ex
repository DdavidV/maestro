defmodule Maestro.TestMatcher do
  @moduledoc false
  use Maestro.Assert.Matcher, name: "test_matcher"

  alias Maestro.Assert.Reason

  # Fails when the assertion entry has "should_fail" => true, echoing back
  # exactly what it received (assertion/actual/context) in the reason's
  # `actual` field so tests can assert on pass-through without any
  # process/agent state — this matcher, like every matcher, is static code.
  def match(assertion, actual, context) do
    if Map.get(assertion, "should_fail", false) do
      {:error, [Reason.new(:test_matcher_saw, assertion, {assertion, actual, context})]}
    else
      :ok
    end
  end
end

defmodule Maestro.TestMatcherAlwaysOk do
  @moduledoc false
  use Maestro.Assert.Matcher, name: "test_matcher_always_ok"

  def match(_assertion, _actual, _context), do: :ok
end
