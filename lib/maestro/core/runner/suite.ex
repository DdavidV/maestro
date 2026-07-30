defmodule Maestro.Core.Runner.Suite do
  @moduledoc """
  Runs a single resolved suite to completion.

  Executes the suite's testcases sequentially, in order, via
  `Maestro.Core.Runner.Testcase.run/1` (fresh state per testcase).
  A suite's own status is the aggregate of its testcases:
  `:ok` only if every testcase is `:ok`, else `:error`.

  Broadcasts `{:testcase_result, suite.id, testcase_run_result}` via
  `Maestro.Core.Runner.Broadcaster` right after each testcase finishes, so
  a LiveView watching `run_id` can show per-testcase progress live rather
  than only learning about this suite's outcome once the whole suite (all
  of its testcases) finishes.
  """

  alias Maestro.Core.Runner.Broadcaster
  alias Maestro.Core.Runner.Testcase

  @spec run(Maestro.run_id(), Maestro.suite()) :: Maestro.suite_run_result()
  def run(run_id, suite) do
    testcases =
      Enum.map(suite.testcases, fn testcase ->
        testcase_run_result = Testcase.run(testcase)
        Broadcaster.broadcast(run_id, {:testcase_result, suite.id, testcase_run_result})
        testcase_run_result
      end)

    status = if Enum.all?(testcases, &(&1.status == :ok)), do: :ok, else: :error
    %{id: suite.id, status: status, testcases: testcases}
  end
end
