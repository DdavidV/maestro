# Scenarios: reusable step sequences

A scenario is a named, reusable sequence of [steps](suite.md#steps)
typically a common flow like "log in and get a token" that any
[testcase](suite.md) (or another scenario) can call by file path,
avoiding duplicating the same steps across every suite that needs them.

Every example below is a complete scenario file as it would appear under
`<resource_dir>/scenarios/`, and every example has been checked against
the actual schema/resolver behavior.

## Where a scenario file lives

`<resource_dir>/scenarios/<path>.json` see [maestro.md](maestro.md) for
what `resource_dir` is. A step calls a scenario by `<path>`,
extension-less:

```json
{ "scenario": "login_and_get_token", "dataset": { "data": { "username": "alice" } } }
```

resolves `<resource_dir>/scenarios/login_and_get_token.json`. Like
templates and datasets, a scenario can also be written **inline** in
place of that path string see
[step's inline scenario example](suite.md#inline-scenarios-and-templates).

## The shape of a scenario

```json
{
  "name": "login_and_get_token",
  "description": "Logs in as the given user and saves the returned auth token to test state as 'auth_token'.",
  "default_dataset": { "data": { "password": "default-test-password" } },
  "steps": [
    {
      "name": "POST /login",
      "client": "http",
      "template": "login_request",
      "save": [{ "path": "$.token", "as": "auth_token" }]
    }
  ]
}
```

- **`name`** optional, cosmetic display label shown in results/UI.
- **`description`** optional free-text description of what the scenario
  does.
- **`default_dataset`** optional. Default values used to render this
  scenario's steps, merged with the caller's own `dataset` at call time.
  See [How dataset merges with `default_dataset`](#how-dataset-merges-with-default_dataset)
  below.
- **`steps`** required, non-empty list the same two step shapes
  (template-step, scenario-call) documented in
  [suite.md](suite.md#steps), so scenarios can call other scenarios,
  composing flows out of smaller flows.

## A scenario's steps share one dataset

Unlike a testcase's steps (each of which carries its own `dataset`), a
scenario's own steps **do not** declare a `dataset` field at all a
scenario is called with a single dataset (the caller's `dataset`,
merged with this scenario's own `default_dataset`), and *every step in
the scenario* renders directly against that one resolved dataset:

```json
{
  "name": "login_and_get_token",
  "default_dataset": { "data": { "password": "default-test-password" } },
  "steps": [
    { "client": "http", "template": "login_request" }
  ]
}
```

`login_request`'s `{{username}}`/`{{password}}` placeholders are filled
in from whatever dataset the *caller* passed, merged with
`default_dataset` above.

## Calling a scenario

From a testcase (or another scenario):

```json
{
  "scenario": "login_and_get_token",
  "dataset": { "data": { "username": "alice" } }
}
```

- **`scenario`** required a file path or an inline scenario body.
- **`dataset`** optional a file path or inline dataset body, merged
  with the called scenario's own `default_dataset`.

## How `dataset` merges with `default_dataset`

At call time, the caller's `dataset` is shallow-merged over the
scenario's own `default_dataset`, **the caller's fields winning on
collision**:

```json
// scenario's default_dataset
{ "data": { "username": "guest", "password": "default-test-password" } }

// caller's dataset
{ "data": { "username": "alice" } }

// what the scenario's steps actually render against
{ "data": { "username": "alice", "password": "default-test-password" } }
```

`username` came from the caller (it won the collision); `password` fell
through from `default_dataset` since the caller didn't specify one.

If the caller omits `dataset` entirely, `default_dataset` is used as-is.
If **neither** the caller's `dataset` nor the scenario's own
`default_dataset` is present, calling the scenario is a resolve-time
error there's nothing to render its steps with.

This same merge also happens one level up: if the *caller itself* was
reached via an outer scenario call (nested scenarios), that outer
dataset is folded in too, outermost first, innermost (the most specific)
winning see [Resolver merge rules](dataset.md#how-datasets-combine-across-a-call-chain)
for the general rule.

### When the caller's dataset has `rows`

If the caller's `dataset` (or an inherited one) has `rows` instead of
`data`, the scenario's `default_dataset` (if it has `data`) is merged
into **every row**, each row's own fields still winning on collision:

```json
// scenario's default_dataset
{ "data": { "password": "default-test-password" } }

// caller's dataset
{ "rows": [{ "username": "alice" }, { "username": "bob", "password": "secret2" }] }

// what the scenario actually runs against, one row at a time
{ "rows": [
    { "username": "alice", "password": "default-test-password" },
    { "username": "bob", "password": "secret2" }
]}
```

The scenario (and every step inside it) runs once per row, exactly like a
`rows` dataset on a plain template-step (see
[dataset.md](dataset.md#rows-data-driven-iteration)).

Two `rows`-shaped datasets can't be merged with each other (combining two
row tables has no non-surprising default cross product? zip?) if both
the inherited dataset and this scenario's own default *and* the caller's
dataset all somehow have `rows`, that's a resolve-time error rather than
a guess.

## Scenarios calling scenarios

A scenario's own `steps` can themselves be scenario-calls, letting you
compose larger flows out of smaller ones:

```json
{
  "name": "checkout_as_new_user",
  "steps": [
    { "scenario": "signup_and_get_token" },
    { "scenario": "add_item_to_cart", "dataset": { "data": { "sku": "ABC123" } } }
  ]
}
```

Each nested call's dataset merges the same way described above, one
level at a time. A scenario referencing itself (directly or through a
chain of other scenarios) is a resolve-time error (cycle detection), and
there's a configurable maximum nesting depth as a backstop against
pathological (but acyclic) chains see `Maestro.Resources.Resolver.max_scenario_depth/0`.

## Examples

```json
{
  "name": "login_and_get_token",
  "description": "Logs in as the given user and saves the returned auth token to test state as 'auth_token'.",
  "default_dataset": { "data": { "password": "default-test-password" } },
  "steps": [
    {
      "name": "POST /login",
      "client": "http",
      "template": "login_request",
      "save": [{ "path": "$.token", "as": "auth_token" }]
    }
  ]
}
```

## See also

- [suite.md](suite.md#steps) the two step shapes a scenario's `steps`
  (and a testcase's `steps`) share.
- [dataset.md](dataset.md) `data` vs. `rows`, and how datasets merge
  across a call chain in general.
- [template.md](template.md) what a scenario's template-steps actually
  send.
- [maestro.md](maestro.md) running a suite whose testcases call scenarios.
