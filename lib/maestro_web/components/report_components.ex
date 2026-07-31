defmodule MaestroWeb.ReportComponents do
  @moduledoc """
  LiveView-native rendering of a `Maestro.Report.Model.t()`, for
  `MaestroWeb.ReportLive.Show`.
  """

  use Phoenix.Component

  import MaestroWeb.RunComponents, only: [status_badge: 1]

  @doc "The report's top-of-page summary: run id, generated-at, status badge, pass/fail counts."
  attr :model, :map, required: true

  def report_header(assigns) do
    ~H"""
    <div class="mb-6">
      <div class="flex items-center gap-2 mb-1">
        <.status_badge status={@model.status} />
        <span class="text-sm text-base-content/70">
          Generated {@model.generated_at}
        </span>
      </div>
      <div class="flex gap-4 text-sm">
        <span>Total suites: {@model.summary.total}</span>
        <span class="text-success">Passed: {@model.summary.ok}</span>
        <span class="text-error">Failed: {@model.summary.error}</span>
      </div>
    </div>
    """
  end

  @doc "One suite's full report section: status, testcases, steps, assertions, failures."
  attr :suite, :map, required: true

  def report_suite(assigns) do
    ~H"""
    <section id={@suite.anchor} class="card bg-base-100 border border-base-300 p-4 mb-4">
      <h2 class="flex items-center gap-2 font-semibold mb-2">
        <.status_badge status={@suite.status} />
        <span class="font-mono">{@suite.id}</span>
      </h2>

      <.report_testcase :for={testcase <- @suite.testcases} testcase={testcase} />

      <p :if={@suite.testcases == []} class="text-sm text-base-content/70">
        No testcases have finished yet.
      </p>
    </section>
    """
  end

  attr :testcase, :map, required: true

  defp report_testcase(assigns) do
    ~H"""
    <div id={@testcase.anchor} class="ml-4 border-l-2 border-base-300 pl-4 mb-3">
      <h3 class="flex items-center gap-2 font-medium mb-1">
        <.status_badge status={@testcase.status} />
        <span class="font-mono text-sm">{@testcase.id}</span>
      </h3>

      <.report_step :for={step <- @testcase.steps} step={step} />
    </div>
    """
  end

  attr :step, :map, required: true

  defp report_step(assigns) do
    ~H"""
    <div class={[
      "rounded border p-3 mb-2 text-sm",
      @step.status == :error && "border-error/50 bg-error/5",
      @step.status == :ok && "border-base-300"
    ]}>
      <div class="flex items-center gap-2 mb-1">
        <.status_badge status={@step.status} />
        <span class="font-semibold">{@step.name}</span>
        <span :if={@step.client} class="badge badge-soft badge-sm">{@step.client}</span>
      </div>

      <.report_failure :if={@step.dispatch_error} failure={@step.dispatch_error} />

      <p
        :if={@step.assertions == [] and is_nil(@step.dispatch_error)}
        class="text-base-content/70"
      >
        (no assertions)
      </p>

      <.report_assertion :for={assertion <- @step.assertions} assertion={assertion} />
    </div>
    """
  end

  attr :assertion, :map, required: true

  defp report_assertion(assigns) do
    ~H"""
    <div class="mt-2 pl-3 border-l-2 border-base-300">
      <div class="flex items-center gap-2">
        <.status_badge status={@assertion.status} />
        <span class="font-mono">{@assertion.matcher}</span>
      </div>

      <ul class="mt-1 text-xs font-mono text-base-content/70 space-y-0.5">
        <li :if={@assertion.path}>path: {@assertion.path}</li>
        <li>expected: {inspect(@assertion.expected)}</li>
        <li>actual: {inspect(@assertion.actual)}</li>
      </ul>

      <.report_failure :for={failure <- @assertion.failures} failure={failure} />
    </div>
    """
  end

  attr :failure, :map, required: true

  defp report_failure(assigns) do
    ~H"""
    <ul class="mt-1 bg-error/10 rounded p-2 text-xs font-mono space-y-0.5">
      <li :if={@failure.stage}>stage: {@failure.stage}</li>
      <li>reason: {@failure.reason}</li>
      <li :if={@failure.path}>path: {@failure.path}</li>
      <li :if={@failure.kind == :assertion_mismatch}>expected: {inspect(@failure.expected)}</li>
      <li :if={@failure.kind == :assertion_mismatch}>actual: {inspect(@failure.actual)}</li>
      <li :if={@failure.kind == :dispatch_error}>details: {inspect(@failure.details)}</li>
    </ul>
    """
  end
end
