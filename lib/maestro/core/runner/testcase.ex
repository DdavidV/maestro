defmodule Maestro.Core.Runner.Testcase do
  @moduledoc """
  Runs a single resolved testcase to completion.

  A thin wrapper over `Maestro.Core.Runner.Step.run_steps/2`: each testcase
  gets a fresh, empty `saved` state (nothing threads `save` state across
  testcases, only across steps within one testcase — that's
  `Step.run_steps/2`'s own existing model, reused verbatim here, one
  call per testcase).
  """

  alias Maestro.Core.Runner.Step

  @spec run(Maestro.testcase()) :: Maestro.testcase_run_result()
  def run(testcase) do
    {status, {steps, _saved}} = Step.run_steps(testcase.steps)
    %{id: testcase.id, status: status, steps: steps}
  end
end
