defmodule Maestro.Core.Runner.Testcase do
  @moduledoc """
  Runs a single resolved testcase to completion.

  A thin wrapper over `Maestro.Core.Runner.Step.run_steps/2`: each testcase
  gets a fresh, empty `saved` state (nothing threads `save` state across
  testcases, only across steps within one testcase — that's
  `Step.run_steps/2`'s own existing model, reused verbatim here, one
  call per testcase).

  `duration` is the wall-clock microseconds (monotonic clock) the whole
  step sequence took, including any time spent between steps, so it can
  be slightly more than the sum of its steps' own `duration`.
  """

  alias Maestro.Core.Runner.Step

  @spec run(Maestro.testcase()) :: Maestro.testcase_run_result()
  def run(testcase) do
    {duration, {status, {steps, _saved}}} = :timer.tc(fn -> Step.run_steps(testcase.steps) end)
    %{id: testcase.id, status: status, steps: steps, duration: duration}
  end
end
