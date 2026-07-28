# Test plans: grouping suites to run together

A test plan is a named, ordered list of [suites](suite.md), referenced by
file path, meant to be run together as one unit for example, "every
suite that must pass before a nightly deploy." A test plan doesn't
contain any steps/testcases of its own; it only groups existing suite
files.

Every example below is a complete test plan file as it would appear
under `<resource_dir>/test_plans/`, and every example has been checked
against the actual schema/resolver behavior.

## Where a test plan file lives

`<resource_dir>/test_plans/<path>.json` see [maestro.md](maestro.md)
for what `resource_dir` is. A test plan is referenced by `<path>` when
running it: `Maestro.run_test_plan("nightly-regression")`.

Unlike suites/scenarios/templates/datasets, a test plan is **always** a
named file there is no inline form, since a test plan's entire purpose
is to name a stable, reusable *set* of suite files.

## The shape of a test plan

```json
{
  "id": "nightly-regression",
  "name": "Nightly Regression",
  "description": "Every suite that must pass before a nightly deploy.",
  "test_suites": ["checkout/smoke", "checkout/regression", "accounts/regression"]
}
```

- **`id`** required, stable identifier for the test plan.
- **`name`** optional, cosmetic display label shown in results/UI. Has no
  bearing on identity, unlike `id`.
- **`description`** optional free-text description of what this test plan
  covers.
- **`test_suites`** required, non-empty list of unique suite file paths
  (e.g. `"checkout/smoke"`, resolving to
  `<resource_dir>/suites/checkout/smoke.json`). Each entry is resolved
  and run exactly as if that path had been passed directly to
  `Maestro.run/1`'s own list a test plan is purely a named shortcut for
  a list of suite references, nothing more.

## Running a test plan

```elixir
{:ok, run_id} = Maestro.run_test_plan("nightly-regression")
```

This is equivalent to reading the test plan's `test_suites` and calling
`Maestro.run/1` with that list directly same async execution model,
same all-or-nothing resolution (if *any* referenced suite fails to
resolve, nothing runs), same `Maestro.status/1`/`Maestro.result/1`
polling afterward. See [maestro.md](maestro.md) for the full run
lifecycle and how to check results.

An unknown test plan name (missing file, fails schema validation) is
reported before anything runs:

```elixir
Maestro.run_test_plan("does-not-exist")
#=> {:error, {:test_plan_not_found, "does-not-exist"}}
```

## Example

```json
{
  "id": "nightly-regression",
  "name": "Nightly Regression",
  "description": "Every suite that must pass before a nightly deploy.",
  "test_suites": ["checkout/smoke", "checkout/regression", "accounts/regression"]
}
```

## See also

- [suite.md](suite.md) what each entry in `test_suites` actually is.
- [maestro.md](maestro.md) `Maestro.run/1`/`run_test_plan/1` and
  checking a run's status/result.
