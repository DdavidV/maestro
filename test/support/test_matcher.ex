defmodule Maestro.TestMatcher do
  @moduledoc false
  use Maestro.Assert.Matcher, name: "test_matcher"

  # Fails when the assertion entry has "should_fail" => true, echoing back
  # exactly what it received (assertion/actual/context) in the error reason
  # so tests can assert on pass-through without any process/agent state —
  # this matcher, like every matcher, is static code.
  def match(assertion, actual, context) do
    if Map.get(assertion, "should_fail", false) do
      {:error, {:test_matcher_saw, assertion, actual, context}}
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
