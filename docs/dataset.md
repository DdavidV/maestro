# Datasets: reusable test data

A dataset is a named bag of values (or a table of rows) that fills in a
[template](template.md)'s `{{placeholder}}`s. Defining data once as a
dataset, and referencing it by file path, avoids copy-pasting the same
literal values across suites and scenarios, and is what makes
[data-driven iteration](#rows-data-driven-iteration) possible.

Every example below is a complete dataset file as it would appear under
`<resource_dir>/datasets/`, and every example has been checked against the
actual schema/resolver behavior.

## Where a dataset file lives

`<resource_dir>/datasets/<path>.json` see [maestro.md](maestro.md) for
what `resource_dir` is and how it's configured. A [step](suite.md#steps)
(or a scenario call) references a dataset by `<path>`, extension-less:

```json
{ "client": "http", "template": "login_request", "dataset": "test_user" }
```

resolves `<resource_dir>/datasets/test_user.json`. A path may contain
subdirectories for your own organization (e.g. `"checkout/seeded_users"` →
`<resource_dir>/datasets/checkout/seeded_users.json`).

A dataset can also be written **inline**, directly in place of that path
string, when it's small and only used in one place see
[Inline vs. file-based](#inline-vs-file-based) below.

## `data`: a single bag of values

```json
{
  "name": "test_user",
  "description": "Default credentials used by the login scenario in most suites.",
  "data": { "username": "alice", "password": "secret" }
}
```

- **`name`** optional, cosmetic display label shown in results/UI. Has no
  bearing on lookup a dataset is referenced by its *file path*, not its
  `name`.
- **`description`** optional free-text description of what this dataset
  represents.
- **`data`** required (unless using `rows` instead see below). A flat
  object of field name to value. Every field becomes available as
  `{{field_name}}` wherever this dataset is used.

Referencing `"test_user"` from a step's `dataset` fills in
`{{username}}`/`{{password}}` in that step's template:

```json
{
  "client": "http",
  "template": "login_request",
  "dataset": "test_user"
}
```

## `rows`: data-driven iteration

A dataset can instead (or in addition to) define `rows` a list of
objects, one per iteration:

```json
{
  "name": "seeded_users",
  "description": "All users seeded in the staging environment, used to run login as each one.",
  "rows": [
    { "username": "alice", "password": "secret1" },
    { "username": "bob", "password": "secret2" }
  ]
}
```

A [step](suite.md#steps) (or [scenario](scenario.md) call) whose resolved
dataset has `rows` runs **once per row**, producing one result per row,
each row's fields filling in `{{placeholder}}`s for that iteration only:

```json
{
  "name": "login as each seeded user",
  "scenario": "login_and_get_token",
  "dataset": "seeded_users"
}
```

This runs `login_and_get_token` twice once with
`{{username}}` = `"alice"`/`{{password}}` = `"secret1"`, once with
`"bob"`/`"secret2"` each a fully independent execution with its own
result, in row order.

A dataset may define **either** `data` or `rows`, but not both in the same
file (see [scenario.md](scenario.md#how-dataset-merges-with-default_dataset)
for how a `rows`-shaped dataset merges with a plain `data` default from
elsewhere that's a *different* thing than one dataset file declaring
both itself).

## Inline vs. file-based

Anywhere a dataset is referenced (a step's `dataset`, a scenario's
`default_dataset`), you can write the dataset body directly instead of a
file path string:

```json
{
  "client": "http",
  "template": "login_request",
  "dataset": { "data": { "username": "alice", "password": "secret" } }
}
```

This is equivalent to defining a file and referencing it by path, useful
for one-off values that don't need reuse the two forms resolve to the
same shape, so nothing about how the step runs differs.

## Values that can't be static: `$generated`

Some values genuinely can't be written as a fixed literal the obvious
example is "today's date," but the same gap covers random/unique values,
environment-derived config, and anything else that must be computed at
test-run time rather than authored ahead of time. A dataset field can use
a `{"$generated": ...}` marker instead of a plain value:

```json
{
  "name": "order_with_todays_date",
  "data": {
    "order_date": { "$generated": "today" },
    "sku": "ABC123"
  }
}
```

`order_date` is computed fresh **every time this dataset is used** once
per step execution, or once per row for a `rows` dataset, never cached
across a run. See [behaviours.md](behaviours.md#generators) for the full
`$generated` marker shapes and how to write your own generator.

## How datasets combine across a call chain

A step's final render context isn't just its own `dataset` it's the
result of merging every dataset in the chain that produced it (an
inherited dataset from an outer scenario call, a scenario's own
`default_dataset`, and the step's/call's own `dataset`), later entries
winning on field collision. See [scenario.md](scenario.md#how-dataset-merges-with-default_dataset)
for the exact merge rules, including what happens when a `rows` dataset
meets a plain `data` default.

## Examples

A single bag of values:

```json
{
  "name": "test_user",
  "description": "Default credentials used by the login scenario in most suites.",
  "data": { "username": "alice", "password": "secret" }
}
```

A row table for data-driven iteration:

```json
{
  "name": "seeded_users",
  "description": "All users seeded in the staging environment, used to run login as each one.",
  "rows": [
    { "username": "alice", "password": "secret1" },
    { "username": "bob", "password": "secret2" }
  ]
}
```
