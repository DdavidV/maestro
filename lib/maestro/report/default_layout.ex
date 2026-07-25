defmodule Maestro.Report.DefaultLayout do
  @moduledoc """
  Maestro's built-in `Maestro.Report.Layout`: a single self-contained HTML
  document (inline `<style>`, no external CSS/JS/font dependency) meant to
  be opened directly via `file://`, no server required.

  Every suite/testcase/step/assertion in the given `Maestro.Report.Model.t()`
  is rendered unconditionally, including a step with `assertions: []`
  transparency is this module's job, not an optional flourish.

  Built as a `Phoenix.Component` (the `~H` sigil) purely for HEEx's
  templating ergonomics (`:for`, `:if`, safe-by-default interpolation)
  it's invoked as a plain function call (`render/1`), never mounted as a
  LiveView. The resulting `%Phoenix.LiveView.Rendered{}` is turned into a
  plain string via `Phoenix.HTML.Safe.to_iodata/1` +
  `IO.iodata_to_binary/1` (NOT `Phoenix.HTML.safe_to_string/1`, which
  requires the literal `{:safe, iodata}` tuple shape and raises on a bare
  `Rendered` struct) no socket, no connection, no JS.
  """

  use Phoenix.Component

  alias Maestro.Report.Model

  @behaviour Maestro.Report.Layout

  @impl Maestro.Report.Layout
  @spec render(Model.t()) :: String.t()
  def render(model) do
    assigns = %{model: model, style_tag: Phoenix.HTML.raw("<style>#{css()}</style>")}

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>Maestro Report — {@model.run_id}</title>
        {@style_tag}
      </head>
      <body>
        <.header model={@model} />
        <.toc model={@model} />
        <.suite :for={suite <- @model.suites} suite={suite} />
      </body>
    </html>
    """
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  attr :model, :map, required: true

  defp header(assigns) do
    ~H"""
    <header class="m-header">
      <h1>Maestro Report</h1>
      <p class="m-run-id">Run <code>{@model.run_id}</code></p>
      <p class="m-generated-at">Generated {@model.generated_at}</p>
      <div class={"m-badge m-badge-#{@model.status}"}>{@model.status}</div>
      <ul class="m-summary">
        <li>Total suites: {@model.summary.total}</li>
        <li>Passed: {@model.summary.ok}</li>
        <li>Failed: {@model.summary.error}</li>
      </ul>
    </header>
    """
  end

  attr :model, :map, required: true

  defp toc(assigns) do
    ~H"""
    <nav class="m-toc">
      <h2>Contents</h2>
      <ul class="m-toc-suites">
        <li :for={suite <- @model.suites} class="m-toc-suite">
          <a href={"##{suite.anchor}"} class="m-toc-link">
            <span class="m-toc-label">{suite.id}</span>
            <span class={"m-badge m-badge-#{suite.status}"}>{suite.status}</span>
          </a>
        </li>
      </ul>
    </nav>
    """
  end

  attr :suite, :map, required: true

  defp suite(assigns) do
    ~H"""
    <section id={@suite.anchor} class="m-suite m-page">
      <h2>
        Suite: {@suite.id}
        <span class={"m-badge m-badge-#{@suite.status}"}>{@suite.status}</span>
      </h2>
      <.suite_toc suite={@suite} />
      <.testcase :for={testcase <- @suite.testcases} testcase={testcase} />
    </section>
    """
  end

  attr :suite, :map, required: true

  defp suite_toc(assigns) do
    ~H"""
    <nav :if={@suite.testcases != []} class="m-toc m-suite-toc">
      <h2>Testcases</h2>
      <ul class="m-toc-testcases">
        <li :for={testcase <- @suite.testcases}>
          <a href={"##{testcase.anchor}"} class="m-toc-link">
            <span class="m-toc-label">{testcase.id}</span>
            <span class={"m-badge m-badge-#{testcase.status}"}>{testcase.status}</span>
          </a>
        </li>
      </ul>
    </nav>
    """
  end

  attr :testcase, :map, required: true

  defp testcase(assigns) do
    ~H"""
    <section id={@testcase.anchor} class="m-testcase">
      <h3>
        Testcase: {@testcase.id}
        <span class={"m-badge m-badge-#{@testcase.status}"}>{@testcase.status}</span>
      </h3>
      <.step :for={step <- @testcase.steps} step={step} />
    </section>
    """
  end

  attr :step, :map, required: true

  defp step(assigns) do
    ~H"""
    <div class={"m-step m-step-#{@step.status}"}>
      <h4>{@step.name} <span class="m-client">{@step.client}</span></h4>
      <.failure_row :if={@step.dispatch_error} failure={@step.dispatch_error} />
      <p :if={@step.assertions == [] and is_nil(@step.dispatch_error)} class="m-no-assertions">
        (no assertions)
      </p>
      <.assertion :for={assertion <- @step.assertions} assertion={assertion} />
    </div>
    """
  end

  attr :assertion, :map, required: true

  defp assertion(assigns) do
    ~H"""
    <div class={"m-assertion m-assertion-#{@assertion.status}"}>
      <p><strong>{@assertion.matcher}</strong> — {@assertion.status}</p>
      <.failure_row :for={failure <- @assertion.failures} failure={failure} />
    </div>
    """
  end

  attr :failure, :map, required: true

  defp failure_row(assigns) do
    ~H"""
    <ul class="m-failure">
      <li :if={@failure.stage}>stage: {@failure.stage}</li>
      <li>reason: {@failure.reason}</li>
      <li :if={@failure.path}>path: {@failure.path}</li>
      <li :if={@failure.kind == :assertion_mismatch}>expected: {inspect(@failure.expected)}</li>
      <li :if={@failure.kind == :assertion_mismatch}>actual: {inspect(@failure.actual)}</li>
      <li :if={@failure.kind == :dispatch_error}>details: {inspect(@failure.details)}</li>
    </ul>
    """
  end

  defp css do
    """
    body { font-family: -apple-system, sans-serif; margin: 2rem; color: #1a1a1a; }
    .m-badge { display: inline-block; padding: .1rem .5rem; border-radius: .25rem; font-size: .8rem; flex-shrink: 0; }
    .m-badge-ok { background: #d4edda; color: #155724; }
    .m-badge-error { background: #f8d7da; color: #721c24; }
    .m-badge-running, .m-badge-pending { background: #eee; color: #555; }
    .m-suite, .m-testcase { border-left: 3px solid #ddd; padding-left: 1rem; margin: 1rem 0; }
    .m-step { border: 1px solid #eee; border-radius: .25rem; padding: .5rem 1rem; margin: .5rem 0; }
    .m-step-error { border-color: #f5b5bb; }
    .m-failure { background: #fff5f5; padding: .5rem 1rem; }

    .m-toc {
      background: #f8f9fa;
      border: 1px solid #e5e7eb;
      border-radius: .5rem;
      padding: 1rem 1.5rem;
      margin: 1.5rem 0;
      max-width: 32rem;
    }
    .m-toc h2 { margin-top: 0; font-size: 1rem; text-transform: uppercase; letter-spacing: .03em; color: #666; }
    .m-toc-suites, .m-toc-testcases { list-style: none; margin: 0; padding: 0; }
    .m-toc-suite { margin: .5rem 0; }
    .m-toc-link {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: .75rem;
      padding: .3rem .5rem;
      border-radius: .3rem;
      text-decoration: none;
      color: #1a1a1a;
    }
    .m-toc-link:hover { background: #eef1f4; }
    .m-toc-suite > .m-toc-link { font-weight: 600; }
    .m-toc-label { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

    /* Printed/PDF pages are exactly A4, per convention. Only affects
       print/export output; on-screen viewing is unaffected. */
    @page {
      size: A4;
      margin: 2cm;
    }

    /* Each suite starts on its own printed/PDF page; the top border is
       just a visual divider on-screen where page breaks don't apply. */
    .m-page {
      break-before: page;
      page-break-before: always;
      border-top: 2px dashed #ccc;
      padding-top: 1.5rem;
    }
    .m-page:first-of-type { border-top: none; padding-top: 0; }
    """
  end
end
