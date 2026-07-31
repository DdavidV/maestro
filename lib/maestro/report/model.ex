defmodule Maestro.Report.Model do
  @moduledoc """
  Builds a presentation-ready tree from a `t:Maestro.run_result/0`, for a
  `Maestro.Report.Layout` to render.

  Pure data assembly, no HTML/HEEx here deliberately: this is independently
  testable on its own, and is the actual contract a host's custom
  `Maestro.Report.Layout` renders against, not the raw `run_result` (whose
  `assertions`/`response` fields carry matcher- and client-internal structs
  a layout shouldn't need to know about).

  Every suite/testcase/step in the input appears in the output, in the
  same order, with none filtered out transparency is a model-building
  guarantee, not a rendering-layer nicety. A step with `assertions: []`
  still gets a `t:step_model/0` entry (with `assertions: []`), never
  dropped, since a report should show every step that ran, not just the
  ones with something to assert.
  """

  alias Maestro.Assert.AssertionResult
  alias Maestro.Assert.Reason
  alias Maestro.Client

  @typedoc """
  One rendered mismatch row a projection of either a
  `Maestro.Assert.Reason.t()` (`kind: :assertion_mismatch`) or a
  `Maestro.Client.Error.t()` (`kind: :dispatch_error`) into one shape a
  single component can render generically, without branching per matcher
  or per client. `stage`/`details` are only ever set for
  `:dispatch_error`; `expected`/`actual`/`path` only for
  `:assertion_mismatch`.
  """
  @type failure_row :: %{
          kind: :assertion_mismatch | :dispatch_error,
          reason: atom,
          expected: term,
          actual: term,
          path: String.t() | nil,
          stage: Client.Error.stage() | nil,
          details: term
        }

  @type assertion_model :: %{
          status: :ok | :error,
          matcher: String.t(),
          path: String.t() | nil,
          expected: term,
          actual: term,
          failures: [failure_row]
        }

  @type step_model :: %{
          name: String.t(),
          status: :ok | :error,
          client: String.t() | nil,
          rendered: Client.rendered() | nil,
          dispatch_error: failure_row | nil,
          assertions: [assertion_model]
        }

  @type testcase_model :: %{
          id: String.t(),
          anchor: String.t(),
          status: :ok | :error,
          steps: [step_model]
        }

  @type suite_model :: %{
          id: String.t(),
          anchor: String.t(),
          status: :pending | :running | :ok | :error,
          testcases: [testcase_model]
        }

  @type summary :: %{total: non_neg_integer, ok: non_neg_integer, error: non_neg_integer}

  @type t :: %{
          run_id: Maestro.run_id(),
          status: Maestro.run_status(),
          generated_at: DateTime.t(),
          summary: summary,
          suites: [suite_model]
        }

  @doc """
  Builds a `t:t/0` from `run_result`.

  Never raises on a partial/`:running` run_result every field this walks
  is already present (possibly empty) at every status
  (`t:Maestro.suite_run_result/0`'s `testcases` is `[]` until that suite
  starts, same for a testcase's `steps`), so this can build a report for
  a still-running run, not only a finished one.
  """
  @spec build(Maestro.run_result()) :: t()
  def build(run_result) do
    suites = Enum.map(run_result.suites, &build_suite/1)

    %{
      run_id: run_result.run_id,
      status: run_result.status,
      generated_at: DateTime.utc_now(),
      summary: summarize(suites),
      suites: suites
    }
  end

  defp summarize(suites) do
    ok = Enum.count(suites, &(&1.status == :ok))
    error = Enum.count(suites, &(&1.status == :error))
    %{total: length(suites), ok: ok, error: error}
  end

  defp build_suite(suite) do
    %{
      id: suite.id,
      anchor: anchor("suite", suite.id),
      status: suite.status,
      testcases: Enum.map(suite.testcases, &build_testcase(suite.id, &1))
    }
  end

  defp build_testcase(suite_id, testcase) do
    %{
      id: testcase.id,
      anchor: anchor("testcase", suite_id <> "/" <> testcase.id),
      status: testcase.status,
      steps: Enum.map(testcase.steps, &build_step/1)
    }
  end

  defp build_step(%{response: %Client.Error{} = error} = step) do
    %{
      name: step.name,
      status: step.status,
      client: step.client,
      rendered: step.rendered,
      dispatch_error: dispatch_failure_row(error),
      assertions: []
    }
  end

  defp build_step(step) do
    %{
      name: step.name,
      status: step.status,
      client: step.client,
      rendered: step.rendered,
      dispatch_error: nil,
      assertions: Enum.map(step.assertions, &build_assertion/1)
    }
  end

  defp build_assertion(%AssertionResult{} = result) do
    %{
      status: result.status,
      matcher: Map.get(result.assertion, :matcher, "?"),
      path: Map.get(result.assertion, :path),
      expected: Map.get(result.assertion, :expected),
      actual: result.actual,
      failures: Enum.map(result.reasons, &assertion_failure_row/1)
    }
  end

  defp assertion_failure_row(%Reason{} = reason) do
    %{
      kind: :assertion_mismatch,
      reason: reason.reason,
      expected: reason.expected,
      actual: reason.actual,
      path: reason.path,
      stage: nil,
      details: nil
    }
  end

  defp dispatch_failure_row(%Client.Error{} = error) do
    %{
      kind: :dispatch_error,
      reason: error.reason,
      expected: nil,
      actual: nil,
      path: nil,
      stage: error.stage,
      details: error.details
    }
  end

  defp anchor(prefix, id), do: prefix <> "-" <> slug(id)

  defp slug(id) do
    id
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
  end
end
