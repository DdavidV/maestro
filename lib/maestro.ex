defmodule Maestro do
  @moduledoc """
  Maestro's main API, and the home of the types used throughout Maestro.
  """

  @typedoc """
  A single entry in the list `run/1` accepts: a named suite reference (a
  file path, resolved via `Maestro.Resources.Resolver.resolve/1`), or an
  ad-hoc suite literal supplied directly, never persisted to a file. Either
  way this is the *unresolved* form, JSON-decoded, string-keyed, and
  possibly still holding reference strings for its templates/scenarios/
  datasets. `run/1` sends it through `Maestro.Resources.Resolver.resolve/1`
  the same as a file-based suite before it's runnable. See `t:suite/0` for
  the resolved shape.
  """
  @type suite_entry :: String.t() | map()

  @typedoc """
  A resolved Maestro test suite, as returned by
  `Maestro.Resources.Resolver.resolve/1` (see `priv/schemas/suite.schema.json`).
  `id` is required and is the suite's stable identity within a run,
  independent of its file path (which resolves the file)
  and of `name` (a purely display-only label).
  """
  @type suite :: %{
          required(:id) => String.t(),
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:tags) => [String.t()],
          required(:testcases) => [testcase()]
        }

  @typedoc """
  A single testcase within a resolved suite (see `t:suite/0`). `id` is
  required and must be unique among the testcases in its suite,
  `Maestro.Resources.Resolver` enforces this at resolve time.
  `name` is purely a display label, same as `t:suite/0`'s.
  """
  @type testcase :: %{
          required(:id) => String.t(),
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          required(:steps) => [step()]
        }

  @typedoc """
  A single entry in a fully resolved step sequence, as produced by
  `Maestro.Resources.Resolver` and consumed by `Maestro.Core.Runner.Step`.
  Either a `t:template_step/0` (renders `template` and dispatches to `client`)
  or a `t:scenario_step/0` (recurses into the resolved scenario's own `steps`).
  `dataset` is always present on both shapes after resolution, even though it's
  optional pre-resolution on a scenario call the Resolver merges and threads it down
  unconditionally.
  """
  @type step :: template_step() | scenario_step()

  @type template_step :: %{
          optional(:name) => String.t(),
          required(:client) => String.t(),
          required(:template) => resolved_template(),
          required(:dataset) => dataset_body(),
          optional(:assert) => [assertion()],
          optional(:save) => [save_entry()]
        }

  @type scenario_step :: %{
          optional(:name) => String.t(),
          required(:scenario) => resolved_scenario(),
          required(:dataset) => dataset_body()
        }

  @typedoc """
  A resolved template body, the shape a `template` reference (file path or
  inline) resolves to. (See `priv/schemas/template.schema.json#/$defs/body`).
  `options` is always present after resolution (defaults to `%{}` if the author omitted it)
  `payload`'s (and `options`'s) own fields are an open, author-defined vocabulary filled in
  by interpolation.
  """
  @type resolved_template :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          required(:clients) => [String.t()],
          required(:payload) => map() | String.t(),
          required(:options) => map()
        }

  @typedoc """
  A resolved scenario body. `default_dataset` and `steps` are always
  present after resolution `Maestro.Resources.Resolver` populates both
  unconditionally, even when the original scenario/call omitted a dataset.
  """
  @type resolved_scenario :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          required(:default_dataset) => dataset_body(),
          required(:steps) => [step()]
        }

  @typedoc """
  A resolved dataset body (see `priv/schemas/dataset.schema.json#/$defs/body`
  and `Maestro.Resources.Resolver`) always one shape or the other, never
  both, and never absent on a step that successfully resolved.
  """
  @type dataset_body :: %{data: dataset_values()} | %{rows: [dataset_values()]}

  @typedoc """
  A single row, or a dataset's "data" bag arbitrary JSON-decoded fields.
  Field names are author-defined and open-ended.
  """
  @type dataset_values :: %{String.t() => term()}

  @typedoc """
  A `save` entry: extracts a value from a step's response into named state.
  """
  @type save_entry :: %{path: String.t(), as: String.t()}

  @typedoc """
  A single check run against a step's result, dispatched to a registered
  `Maestro.Assert.Matcher` by `matcher` name. `matcher` is always present
  after resolution — `Maestro.Resources.Resolver` fills in `"json_match"` if
  the author omitted it. `expected` is required; `path` is optional and
  `json_match`-specific (other matchers may ignore it or give it their own
  meaning). A matcher may attach further, matcher-specific fields beyond
  these three; those aren't modeled here, same tradeoff as `dataset_values`.
  """
  @type assertion :: %{
          required(:matcher) => String.t(),
          required(:expected) => term(),
          optional(:path) => String.t()
        }

  @typedoc "Opaque run identifier returned by `run/1`. Callers must not parse it."
  @type run_id :: String.t()

  @typedoc """
  A run's aggregate status. `:not_found` is only ever returned by `status/1`/
  `result/1`, never stored `run/1` itself never returns it.
  """
  @type run_status :: :running | :ok | :error | :not_found

  @typedoc """
  A lightweight, per-suite progress view — same suite ordering and status
  values as `t:run_result/0`'s `suites`, without the steps/assertions
  payload. What `status/1` returns.
  """
  @type run_progress :: %{
          run_id: run_id(),
          status: run_status(),
          suites: [%{id: String.t(), status: :pending | :running | :ok | :error}]
        }

  @typedoc """
  One row of a workspace's run history, as returned by
  `Maestro.Core.Runner.list_for_workspace/1` — id, when it started, its
  current aggregate status, and how many suites it covers, without any
  suite/testcase/step detail (fetch `t:run_result/0` via `result/1` for that,
  scoped to one `run_id` at a time).
  """
  @type run_summary :: %{
          run_id: run_id(),
          started_at: DateTime.t(),
          status: run_status(),
          suite_count: non_neg_integer
        }

  @typedoc """
  One suite's outcome within a run. `testcases` is `[]` until that suite
  starts executing.
  """
  @type suite_run_result :: %{
          id: String.t(),
          status: :pending | :running | :ok | :error,
          testcases: [testcase_run_result]
        }

  @typedoc """
  One testcase's outcome within a suite run. `steps` is exactly
  `Maestro.Core.Runner.Step.run_steps/2`'s own `[step_result]` return value,
  reused verbatim (already nests `Maestro.Assert.AssertionResult.t()`
  inside each step) no re-wrapping.
  """
  @type testcase_run_result :: %{
          id: String.t(),
          status: :ok | :error,
          steps: [Maestro.Core.Runner.Step.step_result()]
        }

  @typedoc """
  The full accumulated outcome of a `run/1` call, as returned by `result/1`.
  `suites` is in the same order as the `entries` list passed to `run/1`.
  Available (and correct, if partial) while the run is still `:running`
  every suite entry is written exactly once, after that suite is fully
  done, so a partial read is never a torn/half-written record.
  """
  @type run_result :: %{
          run_id: run_id(),
          status: run_status(),
          suites: [suite_run_result]
        }

  @doc """
  Resolves and runs `entries` (a mix of named suite references and/or inline
  suite maps) as one run, within `workspace` (see `Maestro.Workspaces`) —
  every file-path entry, and every reference a resolved suite makes to a
  scenario/template/dataset, is resolved against that one workspace's own
  directory only.

  Resolution is fully synchronous and all-or-nothing: every entry is
  resolved via `Maestro.Resources.Resolver.resolve/2` before this function
  returns anything. If **any** entry fails to resolve, this returns
  `{:error, resolve_errors}` (a list of `{index, reason}` pairs, `index`
  being that entry's position in `entries`) and **nothing runs** — not even
  entries that resolved fine. Only once every entry resolves does execution
  actually start, in the background: this returns `{:ok, run_id}`
  immediately, and the resolved suites execute sequentially (suite by
  suite, testcase by testcase, matching `Maestro.Core.Runner.Step`'s
  existing sequential model) while `status/1`/`result/1` can be polled for
  progress and results.

  `entries` must be a list `{:error, :invalid_entries}` is returned
  synchronously (no run started) if it isn't.
  """
  @spec run(Maestro.Workspaces.Workspace.t(), [suite_entry]) ::
          {:ok, run_id} | {:error, :invalid_entries | [{non_neg_integer, term}]}
  def run(workspace, entries), do: Maestro.Core.Runner.run(workspace, entries)

  @doc """
  Fetches the named test plan (see `priv/schemas/test_plan.schema.json`)
  within `workspace` and runs its `test_suites` exactly as if that list had
  been passed to `run/2` directly same async execution model, same
  all-or-nothing resolution, same `status/1`/`result/1` polling afterward.

  Returns `{:error, {:test_plan_not_found, name}}` if `name` doesn't resolve
  to a valid test plan file (missing, unreadable, or fails schema
  validation) before anything runs. A test plan only references suites by
  file path (see the schema); if any of those suite files then fail to
  resolve, that's reported the same way `run/2` itself reports it
  `{:error, resolve_errors}`.
  """
  @spec run_test_plan(Maestro.Workspaces.Workspace.t(), String.t()) ::
          {:ok, run_id}
          | {:error,
             {:test_plan_not_found, String.t()} | :invalid_entries | [{non_neg_integer, term}]}
  def run_test_plan(workspace, name), do: Maestro.Core.Runner.run_test_plan(workspace, name)

  @doc """
  A lightweight, per-suite progress view for `run_id`: which suites are
  pending, which is running, which are finished (and their outcome) —
  without the full step/assertion payload `result/1` carries.
  """
  @spec status(run_id) :: {:ok, run_progress} | {:error, :not_found}
  def status(run_id), do: Maestro.Core.Runner.status(run_id)

  @doc """
  The result for `run_id`, optionally scoped down to one suite and, within
  it, one testcase both looked up by id, not index.

  `result(run_id)` returns the full `t:run_result/0` tree, available (and
  correct, if partial) while the run is still in progress.
  `result(run_id, suite_id)` returns just that `t:suite_run_result/0`.
  `result(run_id, suite_id, testcase_id)` returns just that
  `t:testcase_run_result/0`. `{:error, :not_found}` covers an unknown
  `run_id`, an unknown `suite_id`, or a `testcase_id` that doesn't match any
  testcase in that suite (scoped, not a global testcase-id search) alike.

  A `suite_id` that appears more than once across the entries passed to
  `run/1` (ids are only guaranteed unique *within* one suite file, not
  across independently-referenced suites in the same run) resolves to the
  first match, in the same order the suites were passed to `run/1`.
  """
  @spec result(run_id) :: {:ok, run_result} | {:error, :not_found}
  @spec result(run_id, String.t()) :: {:ok, suite_run_result} | {:error, :not_found}
  @spec result(run_id, String.t(), String.t()) ::
          {:ok, testcase_run_result} | {:error, :not_found}
  def result(run_id), do: Maestro.Core.Runner.result(run_id)
  def result(run_id, suite_id), do: Maestro.Core.Runner.result(run_id, suite_id)

  def result(run_id, suite_id, testcase_id),
    do: Maestro.Core.Runner.result(run_id, suite_id, testcase_id)

  @doc """
  Renders `run_id`'s current result as a self-contained HTML report
  string, without writing it anywhere. See `Maestro.Report.render/2`.
  """
  @spec render_report(run_id, module) :: {:ok, String.t()} | {:error, :not_found}
  def render_report(run_id, layout \\ Maestro.Report.Layout.configured()),
    do: Maestro.Report.render(run_id, layout)

  @doc """
  Renders and writes `run_id`'s report to disk, under
  `Maestro.Report.report_dir/0`'s per-workspace subdirectory (see
  `Maestro.Report.report_path/1`). Called automatically after every
  `run/1`/`run_test_plan/1` completes, unless disabled via
  `config :maestro, :auto_report, false`. See `Maestro.Report.generate/2`.
  """
  @spec generate_report(run_id, module) ::
          :ok | {:error, :not_found | {:write_failed, term}}
  def generate_report(run_id, layout \\ Maestro.Report.Layout.configured()),
    do: Maestro.Report.generate(run_id, layout)
end
