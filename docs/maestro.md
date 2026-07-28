# Running Maestro: `Maestro.run/1` and checking results

This covers the public API for actually executing a
[suite](suite.md)/[test plan](test_plan.md) you've authored, and reading
back what happened. For *writing* suites/scenarios/templates/datasets,
see their own docs; this page is about running them.

Every example below has been checked against the actual `Maestro`
module's behavior.

## Where resources are resolved from

Suites, scenarios, templates, and datasets referenced by file path are
all read from one configured directory, `resource_dir`:

```
<resource_dir>/suites/<path>.json
<resource_dir>/scenarios/<path>.json
<resource_dir>/datasets/<path>.json
<resource_dir>/templates/<path>.json
<resource_dir>/test_plans/<path>.json
```

`<path>` is exactly the reference string used in a step/scenario/suite
(e.g. `"checkout/seeded_users"`), extension-less, and may contain
subdirectories for your own organization. There is no cache every read
re-parses and re-validates the file, so edits take effect immediately,
with no reload step needed.

Configure it with:

```elixir
config :maestro, :resource_dir, "/path/to/your/resources"
```

Defaults to `priv/resources` under Maestro's own `priv_dir` if unset.

## Running suites: `Maestro.run/1`

```elixir
{:ok, run_id} = Maestro.run(["checkout/smoke", "accounts/smoke"])
```

`run/1` takes a list where each entry is either a suite file path
(a string) or an inline suite map (see [suite.md](suite.md) for the
suite shape either way):

```elixir
suite = %{
  "id" => "smoke_suite",
  "testcases" => [
    %{
      "id" => "tc1",
      "steps" => [
        %{
          "client" => "http",
          "template" => %{"clients" => ["http"], "payload" => %{"a" => 1}},
          "dataset" => %{"data" => %{"a" => 1}}
        }
      ]
    }
  ]
}

{:ok, run_id} = Maestro.run([suite])
```

Resolution is fully synchronous and all-or-nothing: every entry is
resolved before `run/1` returns anything. If **any** entry fails to
resolve (a missing file, a broken reference, a schema violation), this
returns `{:error, resolve_errors}` a list of `{index, reason}` pairs
and **nothing runs**, not even entries that resolved fine:

```elixir
Maestro.run(["checkout/smoke", "does/not/exist"])
#=> {:error, [{1, :not_found}]}
```

A top-level suite reference that can't be found at all fails with a bare
reason like `:not_found` above; a suite that *is* found but has a broken
reference somewhere inside it (an unresolvable scenario/template/dataset)
fails with a path-enriched reason instead, pinpointing exactly where in
the suite the problem is see `Maestro.Resources.Resolver`'s own
documentation for that shape.

Once every entry resolves, `run/1` returns `{:ok, run_id}` immediately
execution happens in the background, suite by suite, testcase by
testcase, sequentially. Passing something other than a list is rejected
synchronously, no run started:

```elixir
Maestro.run(%{"not" => "a list"})
#=> {:error, :invalid_entries}
```

## Running a test plan: `Maestro.run_test_plan/1`

```elixir
{:ok, run_id} = Maestro.run_test_plan("nightly-regression")
```

Fetches the named [test plan](test_plan.md) and runs its `test_suites`
exactly as if that list had been passed to `run/1` directly same
async execution model, same all-or-nothing resolution.

```elixir
Maestro.run_test_plan("does-not-exist")
#=> {:error, {:test_plan_not_found, "does-not-exist"}}
```

## Checking progress: `Maestro.status/1`

A lightweight, per-suite progress view which suites are pending, which
is running, which are finished (and their outcome) without the full
step/assertion payload:

```elixir
{:ok, progress} = Maestro.status(run_id)
#=> {:ok, %{
#     run_id: run_id,
#     status: :running,
#     suites: [%{id: "checkout-flow", status: :running}, %{id: "accounts-flow", status: :pending}]
#   }}
```

`status` is one of `:running`, `:ok`, or `:error` at both the run level
and per-suite (plus `:pending` for a suite that hasn't started yet, per
suite only). An unknown `run_id` returns `{:error, :not_found}`.

A simple poll loop, waiting for a run to finish:

```elixir
defp wait_until_done(run_id) do
  {:ok, progress} = Maestro.status(run_id)

  if progress.status in [:ok, :error] do
    progress
  else
    Process.sleep(50)
    wait_until_done(run_id)
  end
end
```

## Reading full results: `Maestro.result/1,2,3`

```elixir
{:ok, result} = Maestro.result(run_id)
```

Returns the full accumulated `run_result` every suite, every testcase,
every step's outcome, including rendered payload/response and every
assertion's pass/fail detail (`Maestro.Core.Runner.Step.step_result/0`).
Available (and correct, if partial) while the run is still `:running`
a suite's entry is only ever written once, after that suite fully
finishes, so a partial read is never a half-written record.

Scope down to just one suite, or one testcase within it, both looked up
by `id` (not index):

```elixir
{:ok, suite_result} = Maestro.result(run_id, "checkout-flow")
{:ok, testcase_result} = Maestro.result(run_id, "checkout-flow", "add-to-cart-and-pay")
```

`{:error, :not_found}` covers an unknown `run_id`, an unknown `suite_id`,
or a `testcase_id` that doesn't match any testcase in that suite (scoped
to that suite, not a global search).

A `suite_id` that appears more than once across the entries passed to
`run/1` (suite ids are only guaranteed unique *within* one suite file,
not across independently-referenced suites in the same run) resolves to
the first match, in the order the suites were passed to `run/1`.

## Generating an HTML report

A run's result is also rendered automatically to a self-contained HTML
report after every `run/1`/`run_test_plan/1` completes see
[report.md](report.md) for generating one manually, what it contains,
disabling auto-generation, and writing your own report layout.

## Putting it together

```elixir
{:ok, run_id} = Maestro.run_test_plan("nightly-regression")

final = wait_until_done(run_id)

case final.status do
  :ok -> IO.puts("All suites passed.")
  :error -> IO.puts("Something failed see Maestro.result(#{inspect(run_id)}).")
end
```

## See also

- [suite.md](suite.md) what you're running.
- [test_plan.md](test_plan.md) grouping suites together.
- [behaviours.md](behaviours.md) registering the clients/matchers/
  generators a suite depends on before it can run.
- [report.md](report.md) the HTML report generated from a run's result.
