# Reports: HTML, JUnit XML, and custom formats

After (or during) a [run](maestro.md), Maestro can render its result as a
report in one or more **formats**:

- **HTML** (`Maestro.Report.DefaultLayout`, the default) a self-contained
  file, inline CSS, no server or external assets, meant to be opened
  directly via `file://` or attached to a CI job.
- **JUnit XML** (`Maestro.Report.JUnit`) the test-result format CI
  systems read to show per-test results, history and timings.
- **Your own** any module implementing `Maestro.Report.Format`.

This covers generating reports, choosing formats, where they're written,
what they contain, and how to write your own format.

Every example below has been checked against the actual `Maestro.Report`
code.

## Generating a report

A report is generated **automatically** in every configured format (see
[Report formats](#report-formats)) after every
`Maestro.run/1`/`Maestro.run_test_plan/1` completes you don't need to
call anything yourself for the common case. See
[Disabling automatic generation](#disabling-automatic-generation) to turn
this off.

To generate (or regenerate) every configured format manually:

```elixir
{:ok, paths} = Maestro.generate_reports(run_id)
#=> {:ok, %{Maestro.Report.DefaultLayout => ".../maestro_report_<run_id>.html", ...}}
```

Or just one format, named explicitly (there is no default format):

```elixir
:ok = Maestro.generate_report(run_id, Maestro.Report.DefaultLayout)
:ok = Maestro.generate_report(run_id, Maestro.Report.JUnit)
```

Each writes (or overwrites) a fixed path derived from `run_id` and the
format's file extension see
[Where a report is written](#where-a-report-is-written) below.
`generate_reports/1` writes each format independently: a format that
fails to write (or raises) is reported in
`{:error, [{format, reason}]}` without stopping the others.

To get the HTML itself as a string, with no filesystem write at all
(embedding it elsewhere, streaming it, choosing your own write target):

```elixir
{:ok, html} = Maestro.render_report(run_id, Maestro.Report.DefaultLayout)
{:ok, xml} = Maestro.render_report(run_id, Maestro.Report.JUnit)
```

Both accept `run_id` for a run that's still `:running`, not just a
finished one every field the report needs is already present (possibly
empty) at every point in a run's lifecycle, so you can generate a report
for partial results without waiting for the run to finish.

An unknown `run_id` fails the same way `Maestro.result/1` does:

```elixir
Maestro.render_report("does-not-exist", Maestro.Report.DefaultLayout)
#=> {:error, :not_found}

Maestro.generate_report("does-not-exist", Maestro.Report.DefaultLayout)
#=> {:error, :not_found}
```

`generate_report/2` can also fail on the write itself (disk full,
permission denied):

```elixir
Maestro.generate_report(run_id, Maestro.Report.DefaultLayout)
#=> {:error, {:write_failed, reason}}
```

## Where a report is written

```elixir
Maestro.Report.report_path(run_id, Maestro.Report.DefaultLayout)
#=> "<report_dir>/<workspace_id>/maestro_report_<run_id>.html"

Maestro.Report.report_path(run_id, Maestro.Report.JUnit)
#=> "<report_dir>/<workspace_id>/maestro_report_<run_id>.xml"
```

`report_dir` is configurable:

```elixir
config :maestro, :report_dir, "/path/to/your/reports"
```

Defaults to `priv/reports` under Maestro's own `priv_dir` if unset
same convention `Maestro.Resources.resource_dir/0` uses for suite/
scenario/dataset/template files (see [maestro.md](maestro.md)).
`generate_report/2` creates `report_dir` first if it doesn't exist yet,
and overwrites any existing report file for the same `run_id`.

## Disabling automatic generation

```elixir
config :maestro, :auto_report, false
```

With this set, a report is only ever produced when you call
`Maestro.render_report/2`, `Maestro.generate_report/2` or
`Maestro.generate_reports/1` yourself.

## Report formats

```elixir
config :maestro, :report_formats, [
  Maestro.Report.DefaultLayout,
  Maestro.Report.JUnit
]
```

Every format in this list is written after each run, one file per format
(named by the format's extension, which must therefore be unique in the
list). Unset, it defaults to `[Maestro.Report.DefaultLayout]` just the
HTML report.

There is **no default format**: anything that renders or writes a single
report names its format explicitly. Every configured format, plus the
built-in `html` and `junit` ones, can be fetched on demand by name, whether
or not it's written automatically:

- Elixir: `Maestro.render_report(run_id, Maestro.Report.JUnit)`,
  `Maestro.generate_report(run_id, Maestro.Report.JUnit)`.
- REST: `GET /api/runs/{run_id}/report?format=junit` (rendered, not
  written; `format` is required), `POST /api/runs/{run_id}/report?format=junit`
  (written to disk, returns `path` and `paths`). `POST` without `format`
  writes every configured format and returns each file in `paths`, keyed
  by format name.
- GUI: a run's report page has one "Download" dropdown listing every
  format.

A missing (on `GET`) or unknown `format` gets a `400` listing the available
names.

## JUnit XML

`Maestro.Report.JUnit` (name `junit`, extension `.xml`) maps a run onto
JUnit's structure:

| Maestro | JUnit |
|---|---|
| run | `<testsuites name="Maestro <run_id>">`, with totals |
| suite | `<testsuite name="<suite id>">` |
| testcase | `<testcase name="<testcase id>" classname="<suite id>">` |
| failed assertion | `<failure type="<reason>" message="...">` with every failing step's details |
| dispatch error (interpolation, unknown client, client crash, ...) | `<error type="<reason>" message="...">` |
| a testcase's steps | `<system-out>`: each step's status, client, duration and assertions |
| suite still pending/running (partial report, crashed run) | a `<testcase name="(not finished)">` marked `<skipped>` |
| `duration` | `time`, in seconds |

A failing testcase gets exactly one `<error>` (if any of its steps
couldn't be dispatched at all) or `<failure>` (its steps ran, but an
assertion didn't hold), the same "couldn't run" vs. "ran but wrong"
distinction JUnit itself draws.

A typical CI job triggers a run over REST, polls its status until it
finishes, downloads `GET /api/runs/{run_id}/report?format=junit` into the
job's workspace, and publishes that file as the job's test report (GitLab
`artifacts:reports:junit`, Jenkins' JUnit plugin, a GitHub Actions test
reporter, ...).

## What's in a report

The report shows every suite, testcase, and step from the run's result
(`Maestro.result/1`, see [maestro.md](maestro.md)) nothing is filtered
out. A step with no assertions still appears (with an empty assertions
list), since the point of a report is to show everything that ran, not
just the parts with something to assert.

For each level:

- **Run** `run_id`, overall status, when it was generated, total
  duration, and a summary count of passed/failed suites.
- **Suite** id, status (`:pending`/`:running`/`:ok`/`:error`) and
  duration, each linked from a table of contents at the top of the report.
- **Testcase** id, status and duration.
- **Step** name, status, duration, which client sent it, the rendered
  payload/options actually sent, and either:
  - its **assertions** (each with its matcher name, `expected`/`actual`,
    and if it failed every individual mismatch found, not just the
    first, mirroring how a matcher itself can report multiple problems
    per assertion; see [json_match.md](json_match.md)/[json_schema_match.md](json_schema_match.md)), or
  - a **dispatch error**, if the step never got a response at all (an
    unresolved `{{placeholder}}`, an unregistered client, a client
    `init/2`/`send/2` failure or crash) shown distinctly from an
    assertion failure, since no comparison ever happened to report.

## Writing your own format

A format is a module implementing `Maestro.Report.Format`. Only `render/1`
is required; the optional callbacks default to an HTML report's values:

```elixir
@callback render(Maestro.Report.Model.t()) :: String.t()
@callback name() :: String.t()          # optional, defaults to extension()
@callback extension() :: String.t()     # optional, defaults to "html"
@callback content_type() :: String.t()  # optional, defaults to "text/html"
```

A custom HTML report only needs `render/1`. Configure it in place of the
built-in one (it also takes over the `html` name, since a configured format
shadows a built-in one with the same name):

```elixir
config :maestro, :report_formats, [MyApp.Maestro.ReportLayout, Maestro.Report.JUnit]
```

```elixir
defmodule MyApp.Maestro.ReportLayout do
  @behaviour Maestro.Report.Format

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

A non-HTML format sets the optional callbacks, e.g. a CSV summary:

```elixir
defmodule MyApp.Maestro.CsvReport do
  @behaviour Maestro.Report.Format

  @impl true
  def render(model) do
    rows = for suite <- model.suites, do: "#{suite.id},#{suite.status},#{suite.duration}"
    Enum.join(["suite,status,duration_us" | rows], "\n")
  end

  @impl true
  def name, do: "csv"

  @impl true
  def extension, do: "csv"

  @impl true
  def content_type, do: "text/csv"
end
```

`Maestro.render_report/2`/`Maestro.generate_report/2` take any format
module, configured or not, for a one-off call without touching the global
config:

```elixir
{:ok, html} = Maestro.render_report(run_id, MyApp.Maestro.ReportLayout)
```

### The model shape

```elixir
%{
  run_id: run_id,
  status: :ok,
  generated_at: ~U[2026-01-01 00:00:00Z],
  summary: %{total: 2, ok: 1, error: 1, duration: 1_840_000},
  suites: [
    %{
      id: "checkout-flow",
      anchor: "suite-checkout-flow",
      status: :error,
      duration: 1_200_000,
      testcases: [
        %{
          id: "add-to-cart-and-pay",
          anchor: "testcase-checkout-flow-add-to-cart-and-pay",
          status: :error,
          duration: 1_150_000,
          steps: [
            %{
              name: "POST /cart",
              status: :error,
              client: "http",
              duration: 412_000,
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

- **`duration`** wall-clock time in **microseconds** (integer), measured
  with a monotonic clock. `nil` on a suite that hasn't finished yet;
  `summary.duration` totals every finished suite.
- **`anchor`** a pre-computed, HTML-id-safe slug (used for the built-in
  layout's table-of-contents links) a custom layout can use it the same
  way, or ignore it entirely.
- **`dispatch_error`** set instead of `assertions` (which is `[]` in that
  case) when the step never got a response its shape is the same
  `failure_row` shown above, but with `kind: :dispatch_error` and
  `stage`/`details` filled in instead of `expected`/`actual`/`path`.
- A step that dispatched successfully but has no `assert` entries at all
  still appears, with `assertions: []` not omitted.

## Previewing format changes during development

For iterating on a custom format (or Maestro's own
`Maestro.Report.DefaultLayout`/`Maestro.Report.JUnit`), the
`mix maestro.demo_report` task runs a handful of hand-built demo suites
covering every reportable outcome (passing, several kinds of assertion
failure, a schema-validation failure, an unregistered client, a client
crash) and writes the result in every available format to fixed paths,
`tmp/reports/showcase.<extension>` (`showcase.html`, `showcase.xml`, ...),
so you can just reopen the same files after every change instead of
hunting for `run_id`-named ones:

```bash
mix maestro.demo_report
```

```bash
mix maestro.demo_report --format MyApp.Maestro.ReportLayout
```

This is a developer tool, not a test nothing in it is asserted against.

## See also

- [maestro.md](maestro.md) `Maestro.run/1` and the `run_result` a
  report is built from.
- [suite.md](suite.md#assertions) where the `assert`/matcher results
  shown in a report come from.
- [behaviours.md](behaviours.md) writing a custom client/matcher,
  whose failures also end up in a report.
