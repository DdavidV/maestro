defmodule MaestroWeb.ReportComponents do
  @moduledoc """
  LiveView-native rendering of a `Maestro.Report.Model.t()`, for
  `MaestroWeb.ReportLive.Show`.
  """

  use Phoenix.Component

  import MaestroWeb.CoreComponents, only: [icon: 1]
  import MaestroWeb.RunComponents, only: [status_badge: 1, status_icon: 1, format_datetime: 1]

  @doc "The report's top-of-page summary: run id, generated-at, status badge, pass/fail counts."
  attr :model, :map, required: true

  def report_header(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-px overflow-hidden rounded-box border border-base-300 bg-base-300 md:grid-cols-4">
      <div class="bg-base-100 px-4 py-3.5">
        <div class="text-xs font-medium text-base-content/50">Status</div>
        <div class="mt-2"><.status_badge status={@model.status} /></div>
      </div>
      <div class="bg-base-100 px-4 py-3.5">
        <div class="text-xs font-medium text-base-content/50">Total suites</div>
        <div class="mt-1 text-2xl font-semibold tabular-nums">{@model.summary.total}</div>
      </div>
      <div class="bg-base-100 px-4 py-3.5">
        <div class="text-xs font-medium text-base-content/50">Passed</div>
        <div class="mt-1 text-2xl font-semibold tabular-nums text-success">
          {@model.summary.ok}
        </div>
      </div>
      <div class="bg-base-100 px-4 py-3.5">
        <div class="text-xs font-medium text-base-content/50">Failed</div>
        <div class={[
          "mt-1 text-2xl font-semibold tabular-nums",
          @model.summary.error > 0 && "text-error"
        ]}>
          {@model.summary.error}
        </div>
      </div>
    </div>
    <p class="text-xs text-base-content/50">
      Generated {format_datetime(@model.generated_at)}
    </p>
    """
  end

  @doc "A sticky in-page table of contents linking to each suite/testcase anchor."
  attr :suites, :list, required: true

  def report_toc(assigns) do
    ~H"""
    <nav aria-label="Report contents" class="panel overflow-hidden">
      <div class="section-label border-b border-base-300 px-4 py-2.5">Contents</div>
      <ul class="max-h-[70vh] space-y-0.5 overflow-y-auto p-2">
        <li :for={suite <- @suites}>
          <a
            href={"##{suite.anchor}"}
            class="flex items-center gap-2 rounded-field px-2 py-1.5 text-[0.8125rem] font-medium hover:bg-base-200"
          >
            <.status_icon status={suite.status} class="size-3.5" />
            <span class="truncate font-mono">{suite.id}</span>
          </a>
          <ul :if={suite.testcases != []} class="ml-4 border-l border-base-300 pl-2">
            <li :for={testcase <- suite.testcases}>
              <a
                href={"##{testcase.anchor}"}
                class="flex items-center gap-2 rounded-field px-2 py-1 text-xs text-base-content/70 hover:bg-base-200 hover:text-base-content"
              >
                <.status_icon status={testcase.status} class="size-3" />
                <span class="truncate font-mono">{testcase.id}</span>
              </a>
            </li>
          </ul>
        </li>
      </ul>
    </nav>
    """
  end

  @doc "One suite's full report section: status, testcases, steps, assertions, failures."
  attr :suite, :map, required: true

  def report_suite(assigns) do
    ~H"""
    <section id={@suite.anchor} class="panel scroll-mt-6 overflow-hidden">
      <h2 class="flex items-center gap-3 border-b border-base-300 px-4 py-3">
        <.icon name="hero-beaker" class="size-4 shrink-0 text-base-content/40" />
        <span class="min-w-0 flex-1 truncate font-mono text-sm font-semibold">{@suite.id}</span>
        <.status_badge status={@suite.status} />
      </h2>

      <div class="divide-y divide-base-300">
        <.report_testcase :for={testcase <- @suite.testcases} testcase={testcase} />
      </div>

      <p :if={@suite.testcases == []} class="px-4 py-3 text-sm text-base-content/60">
        No testcases have finished yet.
      </p>
    </section>
    """
  end

  attr :testcase, :map, required: true

  defp report_testcase(assigns) do
    ~H"""
    <div id={@testcase.anchor} class="scroll-mt-6 px-4 py-4">
      <h3 class="mb-3 flex items-center gap-2">
        <.status_icon status={@testcase.status} />
        <span class="font-mono text-[0.8125rem] font-semibold">{@testcase.id}</span>
      </h3>

      <div class="space-y-2">
        <.report_step :for={step <- @testcase.steps} step={step} />
      </div>
    </div>
    """
  end

  attr :step, :map, required: true

  defp report_step(assigns) do
    ~H"""
    <div class={[
      "rounded-field border p-3 text-sm",
      @step.status == :error && "border-error/30 bg-error/[0.03]",
      @step.status != :error && "border-base-300"
    ]}>
      <div class="flex flex-wrap items-center gap-2">
        <.status_icon status={@step.status} class="size-3.5" />
        <span class="font-medium">{@step.name}</span>
        <span
          :if={@step.client}
          class="rounded-md border border-base-300 bg-base-200 px-1.5 py-0.5 font-mono text-xs text-base-content/70"
        >
          {@step.client}
        </span>
      </div>

      <.report_failure :if={@step.dispatch_error} failure={@step.dispatch_error} />

      <p
        :if={@step.assertions == [] and is_nil(@step.dispatch_error)}
        class="mt-1 text-xs text-base-content/50"
      >
        (no assertions)
      </p>

      <div :if={@step.assertions != []} class="mt-2 space-y-2">
        <.report_assertion :for={assertion <- @step.assertions} assertion={assertion} />
      </div>
    </div>
    """
  end

  attr :assertion, :map, required: true

  defp report_assertion(assigns) do
    ~H"""
    <div class="rounded-field bg-base-200/60 px-3 py-2">
      <div class="flex items-center gap-2">
        <.status_badge status={@assertion.status} />
        <span class="font-mono text-xs font-semibold">{@assertion.matcher}</span>
      </div>

      <ul class="mt-1.5 space-y-0.5 font-mono text-xs break-all text-base-content/70">
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
    <div class="mt-2 flex gap-2 rounded-field border border-error/20 bg-error/10 p-2.5 text-error">
      <.icon name="hero-exclamation-triangle-mini" class="mt-px size-4 shrink-0" />
      <ul class="min-w-0 space-y-0.5 font-mono text-xs break-all">
        <li :if={@failure.stage}>stage: {@failure.stage}</li>
        <li class="font-semibold">reason: {@failure.reason}</li>
        <li :if={@failure.path}>path: {@failure.path}</li>
        <li :if={@failure.kind == :assertion_mismatch}>expected: {inspect(@failure.expected)}</li>
        <li :if={@failure.kind == :assertion_mismatch}>actual: {inspect(@failure.actual)}</li>
        <li :if={@failure.kind == :dispatch_error}>details: {inspect(@failure.details)}</li>
      </ul>
    </div>
    """
  end
end
