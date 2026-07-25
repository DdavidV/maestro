defmodule Maestro.Core.Runner.Suite do
  @moduledoc """
  Runs a single resolved suite to completion.

  Executes the suite's testcases sequentially, in order, via
  `Maestro.Core.Runner.Testcase.run/1` (fresh state per testcase).
  A suite's own status is the aggregate of its testcases:
  `:ok` only if every testcase is `:ok`, else `:error`.
  """

  alias Maestro.Core.Runner.Testcase

  @spec run(Maestro.suite()) :: Maestro.suite_run_result()
  def run(suite) do
    testcases = Enum.map(suite.testcases, &Testcase.run/1)
    status = if Enum.all?(testcases, &(&1.status == :ok)), do: :ok, else: :error
    %{id: suite.id, status: status, testcases: testcases}
  end
end
