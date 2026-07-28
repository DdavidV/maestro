# Reports: HTML output for a run

After (or during) a [run](maestro.md), Maestro can render a self-contained
HTML report one file, inline CSS, no server or external assets, meant
to be opened directly via `file://` or attached to a CI job. This covers
generating a report, where it's written, what it contains, and how to
plug in your own layout instead of the built-in one.

Every example below has been checked against the actual `Maestro.Report`
code.

## Generating a report

A report is generated **automatically** after every
`Maestro.run/1`/`Maestro.run_test_plan/1` completes you don't need to
call anything yourself for the common case. See
[Disabling automatic generation](#disabling-automatic-generation) to turn
this off.

To generate (or regenerate) one manually:

```elixir
:ok = Maestro.generate_report(run_id)
```

Writes (or overwrites) the report to a fixed path derived from `run_id`
see [Where a report is written](#where-a-report-is-written) below.

To get the HTML itself as a string, with no filesystem write at all
(embedding it elsewhere, streaming it, choosing your own write target):

```elixir
{:ok, html} = Maestro.render_report(run_id)
```

Both accept `run_id` for a run that's still `:running`, not just a
finished one every field the report needs is already present (possibly
empty) at every point in a run's lifecycle, so you can generate a report
for partial results without waiting for the run to finish.

An unknown `run_id` fails the same way `Maestro.result/1` does:

```elixir
Maestro.render_report("does-not-exist")
#=> {:error, :not_found}

Maestro.generate_report("does-not-exist")
#=> {:error, :not_found}
```

`generate_report/1` can also fail on the write itself (disk full,
permission denied):

```elixir
Maestro.generate_report(run_id)
#=> {:error, {:write_failed, reason}}
```

## Where a report is written

```elixir
Maestro.Report.report_path(run_id)
#=> "<report_dir>/maestro_report_<run_id>.html"
```

`report_dir` is configurable:

```elixir
config :maestro, :report_dir, "/path/to/your/reports"
```

Defaults to `priv/reports` under Maestro's own `priv_dir` if unset
same convention `Maestro.Resources.resource_dir/0` uses for suite/
scenario/dataset/template files (see [maestro.md](maestro.md)).
`generate_report/1` creates `report_dir` first if it doesn't exist yet,
and overwrites any existing report file for the same `run_id`.

## Disabling automatic generation

```elixir
config :maestro, :auto_report, false
```

With this set, a report is only ever produced when you call
`Maestro.render_report/1` or `Maestro.generate_report/1` yourself.

## What's in a report

The report shows every suite, testcase, and step from the run's result
(`Maestro.result/1`, see [maestro.md](maestro.md)) nothing is filtered
out. A step with no assertions still appears (with an empty assertions
list), since the point of a report is to show everything that ran, not
just the parts with something to assert.

For each level:

- **Run** `run_id`, overall status, when it was generated, and a
  summary count of passed/failed suites.
- **Suite** id and status (`:pending`/`:running`/`:ok`/`:error`), each
  linked from a table of contents at the top of the report.
- **Testcase** id and status.
- **Step** name, status, which client sent it, the rendered
  payload/options actually sent, and either:
  - its **assertions** (each with its matcher name, `expected`/`actual`,
    and if it failed every individual mismatch found, not just the
    first, mirroring how a matcher itself can report multiple problems
    per assertion; see [json_match.md](json_match.md)/[json_schema_match.md](json_schema_match.md)), or
  - a **dispatch error**, if the step never got a response at all (an
    unresolved `{{placeholder}}`, an unregistered client, a client
    `init/2`/`send/2` failure or crash) shown distinctly from an
    assertion failure, since no comparison ever happened to report.

## Writing your own layout

`Maestro.Report.DefaultLayout` is a `Maestro.Report.Layout` a behaviour
with a single callback:

```elixir
@callback render(Maestro.Report.Model.t()) :: String.t()
```

A host application can implement its own and point Maestro at it instead
of the built-in one:

```elixir
config :maestro, :report_layout, MyApp.Maestro.ReportLayout
```

```elixir
defmodule MyApp.Maestro.ReportLayout do
  @behaviour Maestro.Report.Layout

  @impl true
  def render(model) do
    """
    <!DOCTYPE html>
    <html>
      <body>
        <h1>Run #{model.run_id} #{model.status}</h1>
        <p>#{model.summary.ok}/#{model.summary.total} suites passed</p>
      </body>
    </html>
    """
  end
end
```

Your `render/1` receives a `Maestro.Report.Model.t()` a plain,
presentation-ready data tree (not the raw `Maestro.run_result/0`), so you
never need to branch on matcher- or client-internal structs yourself; see
[The model shape](#the-model-shape) below for its exact fields.

`Maestro.render_report/2`/`Maestro.generate_report/2` both also accept a
`layout` module directly, as a second argument, for a one-off call
without touching the global config:

```elixir
{:ok, html} = Maestro.render_report(run_id, MyApp.Maestro.ReportLayout)
```

### The model shape

```elixir
%{
  run_id: run_id,
  status: :ok,
  generated_at: ~U[2026-01-01 00:00:00Z],
  summary: %{total: 2, ok: 1, error: 1},
  suites: [
    %{
      id: "checkout-flow",
      anchor: "suite-checkout-flow",
      status: :error,
      testcases: [
        %{
          id: "add-to-cart-and-pay",
          anchor: "testcase-checkout-flow-add-to-cart-and-pay",
          status: :error,
          steps: [
            %{
              name: "POST /cart",
              status: :error,
              client: "http",
              rendered: %{"payload" => %{"sku" => "ABC123"}, "options" => %{"method" => "POST", "url" => "..."}},
              dispatch_error: nil,
              assertions: [
                %{
                  status: :error,
                  matcher: "json_match",
                  expected: 42,
                  actual: 41,
                  failures: [
                    %{kind: :assertion_mismatch, reason: :not_equal, expected: 42, actual: 41, path: "$.total", stage: nil, details: nil}
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

- **`anchor`** a pre-computed, HTML-id-safe slug (used for the built-in
  layout's table-of-contents links) a custom layout can use it the same
  way, or ignore it entirely.
- **`dispatch_error`** set instead of `assertions` (which is `[]` in that
  case) when the step never got a response its shape is the same
  `failure_row` shown above, but with `kind: :dispatch_error` and
  `stage`/`details` filled in instead of `expected`/`actual`/`path`.
- A step that dispatched successfully but has no `assert` entries at all
  still appears, with `assertions: []` not omitted.

## Previewing layout changes during development

For iterating on a custom layout (or Maestro's own
`Maestro.Report.DefaultLayout`), the `mix maestro.demo_report` task runs a
handful of hand-built demo suites covering every reportable outcome
(passing, several kinds of assertion failure, a schema-validation
failure, an unregistered client, a client crash) and writes the result to
a fixed path, `tmp/reports/showcase.html`, so you can just reopen the
same file after every change instead of hunting for a `run_id`-named one:

```bash
mix maestro.demo_report
```

```bash
mix maestro.demo_report --layout MyApp.Maestro.ReportLayout
```

This is a developer tool, not a test nothing in it is asserted against.

## See also

- [maestro.md](maestro.md) `Maestro.run/1` and the `run_result` a
  report is built from.
- [suite.md](suite.md#assertions) where the `assert`/matcher results
  shown in a report come from.
- [behaviours.md](behaviours.md) writing a custom client/matcher,
  whose failures also end up in a report.
