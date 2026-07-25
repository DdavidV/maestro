defmodule Maestro.Core.Runner do
  @moduledoc """
  Orchestrates `Maestro.run/1`/`status/1`/`result/1`: resolves suite
  entries, executes them sequentially in the background, and exposes their
  progress/results via `Maestro.Core.Runner.Store`.

  ## Resolution: synchronous, all-or-nothing

  `run/1` resolves every entry via `Maestro.Resources.Resolver.resolve/1`
  before returning anything nothing is hidden behind an async row someone
  has to poll into to discover a bad file path. If any entry fails, nothing
  runs (not even entries that resolved fine) and the caller gets every
  resolve failure back immediately. Only once every entry resolves does a
  `run_id` get created and execution start in the background.

  ## Execution model

  Once running, resolved suites execute sequentially, suite by suite, each
  one delegated whole to `Maestro.Core.Runner.Suite.run/1` (which in turn
  runs its testcases sequentially via `Maestro.Core.Runner.Testcase.run/1`,
  each a fresh `Maestro.Core.Runner.Step.run_steps/2` call). `Runner` itself
  only orchestrates *between* suites: marking each `:running` before it
  starts and recording its result once `Suite` returns, mirroring the
  same three-layer split `Step` already models one level down
  (suite -> testcase -> step), with `Runner` itself as the fourth layer,
  the one that knows about multiple suites in a single run at all.

  Runs entirely inside an unlinked `Task` (via `Task.Supervisor`, started
  under `Maestro.Supervisor`) so a crashing run can't take down anything
  else, the task body is wrapped in `rescue` so an unexpected exception
  still leaves a queryable `:error` row rather than a run stuck at
  `:running` forever.

  ## Storage

  Progress is written incrementally to `Maestro.Core.Runner.Store`'s ETS
  table as each suite finishes (not per-testcase/per-step keeps write
  volume proportional to suite count). `result/1,2,3` and `status/1` both
  read straight from that table; `status/1` is a lighter-weight projection
  (drops each suite's `testcases`) of the same row `result/1` returns in
  full. `result/2`/`result/3` scope that same row down to a single
  suite/testcase by id (not index), for reporting/UI use cases that want
  one result without walking the whole `run_result` tree. A suite id that
  appears more than once across the entries passed to `run/1` (ids are
  only guaranteed unique *within* one suite file, not across
  independently-referenced suites in the same run) resolves to the first
  match, in the same order the suites were passed to `run/1`.

  Every level of this tree (`run_result` -> `suite_run_result` ->
  `testcase_run_result` -> `step_result` -> `assertion_result`) is kept
  fully intact end to end, nothing here summarizes or discards data
  deliberately, since `Maestro.Report` needs to walk every assertion of
  every step of every testcase of every suite in a run.

  ## Automatic report generation

  Once a run reaches a terminal status (`Store.finalize/1` on ordinary
  completion, `Store.mark_crashed/1` if `execute_run/2` itself raised),
  `Maestro.Report.generate/1` is called for that `run_id` unless
  `config :maestro, :auto_report, false` is set. This happens strictly
  *after* the terminal write, so `status/1`/`result/1` are never delayed
  by it, and any failure (a bad custom `report_layout`, a disk error) is
  caught and logged, never allowed to crash this run's `Task` or affect
  its already-finalized status.
  """

  require Logger

  alias Maestro.Core.Runner.Store
  alias Maestro.Core.Runner.Suite
  alias Maestro.Report
  alias Maestro.Resources
  alias Maestro.Resources.Resolver

  @task_supervisor Maestro.Core.Runner.TaskSupervisor

  @spec run([Maestro.suite_entry()]) ::
          {:ok, Maestro.run_id()} | {:error, :invalid_entries | [{non_neg_integer, term}]}
  def run(entries) when is_list(entries) do
    case resolve_all(entries) do
      {:ok, resolved_suites} -> start_run(resolved_suites)
      {:error, resolve_errors} -> {:error, resolve_errors}
    end
  end

  def run(_entries), do: {:error, :invalid_entries}

  @doc """
  Fetches the named test plan and runs its `test_suites` exactly as if that
  list had been passed to `run/1` directly.
  """
  @spec run_test_plan(String.t()) ::
          {:ok, Maestro.run_id()}
          | {:error,
             {:test_plan_not_found, String.t()} | :invalid_entries | [{non_neg_integer, term}]}
  def run_test_plan(name) do
    case Resources.fetch(:test_plan, name) do
      {:ok, %{"test_suites" => test_suites}} -> run(test_suites)
      {:error, _reason} -> {:error, {:test_plan_not_found, name}}
    end
  end

  @spec status(Maestro.run_id()) :: {:ok, Maestro.run_progress()} | {:error, :not_found}
  def status(run_id) do
    with {:ok, run_result} <- Store.get(run_id) do
      suites = Enum.map(run_result.suites, &Map.take(&1, [:id, :status]))
      {:ok, %{run_id: run_result.run_id, status: run_result.status, suites: suites}}
    else
      :error -> {:error, :not_found}
    end
  end

  @doc """
  The result for `run_id`, optionally scoped down to one suite
  (`suite_id`) and, within it, one testcase (`testcase_id`) both looked
  up by id, not index. `result(run_id)` returns the full `t:Maestro.run_result/0`
  tree; `result(run_id, suite_id)` returns just that
  `t:Maestro.suite_run_result/0`; `result(run_id, suite_id, testcase_id)`
  returns just that `t:Maestro.testcase_run_result/0`. `{:error, :not_found}`
  covers an unknown `run_id`, an unknown `suite_id`, or an unknown
  `testcase_id` (scoped to its suite, not a global testcase-id search) alike.
  """
  @spec result(Maestro.run_id()) :: {:ok, Maestro.run_result()} | {:error, :not_found}
  @spec result(Maestro.run_id(), String.t()) ::
          {:ok, Maestro.suite_run_result()} | {:error, :not_found}
  @spec result(Maestro.run_id(), String.t(), String.t()) ::
          {:ok, Maestro.testcase_run_result()} | {:error, :not_found}
  def result(run_id) do
    case Store.get(run_id) do
      {:ok, run_result} -> {:ok, run_result}
      :error -> {:error, :not_found}
    end
  end

  def result(run_id, suite_id) do
    with {:ok, run_result} <- result(run_id),
         %{} = suite <- Enum.find(run_result.suites, :not_found, &(&1.id == suite_id)) do
      {:ok, suite}
    else
      {:error, :not_found} -> {:error, :not_found}
      :not_found -> {:error, :not_found}
    end
  end

  def result(run_id, suite_id, testcase_id) do
    with {:ok, suite} <- result(run_id, suite_id),
         %{} = testcase <- Enum.find(suite.testcases, :not_found, &(&1.id == testcase_id)) do
      {:ok, testcase}
    else
      {:error, :not_found} -> {:error, :not_found}
      :not_found -> {:error, :not_found}
    end
  end

  defp resolve_all(entries) do
    results =
      entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} -> {index, Resolver.resolve(entry)} end)

    errors = for {index, {:error, reason}} <- results, do: {index, reason}

    if errors == [] do
      {:ok, Enum.map(results, fn {_index, {:ok, suite}} -> suite end)}
    else
      {:error, errors}
    end
  end

  defp start_run(resolved_suites) do
    run_id = generate_run_id()
    :ok = Store.create(run_id, resolved_suites)

    {:ok, _pid} =
      Task.Supervisor.start_child(@task_supervisor, fn -> execute_run(run_id, resolved_suites) end)

    {:ok, run_id}
  end

  defp execute_run(run_id, resolved_suites) do
    resolved_suites
    |> Enum.with_index()
    |> Enum.each(fn {suite, index} -> execute_suite(run_id, index, suite) end)

    Store.finalize(run_id)
    generate_report(run_id)
  rescue
    _exception ->
      Store.mark_crashed(run_id)
      generate_report(run_id)
  end

  defp generate_report(run_id) do
    if Application.get_env(:maestro, :auto_report, true) do
      case Report.generate(run_id) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Maestro report generation failed for #{run_id}: #{inspect(reason)}")
      end
    end
  rescue
    exception ->
      Logger.warning(
        "Maestro report generation crashed for #{run_id}: #{Exception.message(exception)}"
      )
  end

  defp execute_suite(run_id, index, suite) do
    Store.mark_running(run_id, index)
    Store.put_suite_result(run_id, index, Suite.run(suite))
  end

  defp generate_run_id do
    "run_#{System.unique_integer([:positive, :monotonic])}_#{node()}"
  end
end
