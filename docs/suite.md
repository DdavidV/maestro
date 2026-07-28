# Suites: organizing testcases and steps

A suite is a named collection of testcases, each an ordered list of
**steps** either a request sent via a [client](behaviours.md#clients)
using a [template](template.md), or a call into a reusable
[scenario](scenario.md). A suite is the thing you actually
[run](maestro.md).

Every example below is a complete suite file as it would appear under
`<resource_dir>/suites/`, and every example has been checked against the
actual schema/resolver behavior.

## Where a suite file lives

`<resource_dir>/suites/<path>.json` see [maestro.md](maestro.md) for
what `resource_dir` is. A suite is referenced by `<path>` when running it
(`Maestro.run(["checkout/smoke"])`), or can be passed as an inline map
directly to `Maestro.run/1` without a file at all.

## The shape of a suite

```json
{
  "id": "checkout-flow",
  "name": "Checkout Flow",
  "description": "Verifies a logged-in user can add an item to the cart and pay successfully.",
  "tags": ["smoke", "checkout"],
  "testcases": [
    {
      "id": "add-to-cart-and-pay",
      "name": "Add to cart and pay",
      "steps": [
        {
          "scenario": "login_and_get_token",
          "dataset": { "data": { "username": "alice" } }
        },
        {
          "name": "POST /cart",
          "client": "http",
          "template": "add_to_cart_request",
          "dataset": { "data": { "sku": "ABC123", "qty": 1 } },
          "assert": [
            { "matcher": "json_match", "path": "$.total", "expected": 42 }
          ]
        }
      ]
    }
  ]
}
```

- **`id`** required, stable identifier for the suite used to key its
  status/results within a run (see [maestro.md](maestro.md)). Independent
  of the file path used to reference it, and of `name`.
- **`name`** optional, cosmetic display label shown in results/UI. Has no
  bearing on identity or lookup, unlike `id`.
- **`description`** optional free-text description of what the suite
  covers.
- **`tags`** optional list of labels for filtering/grouping suites (e.g.
  `"smoke"`, `"nightly"`).
- **`testcases`** required, non-empty list. Each testcase has its own
  `id` (must be unique *within this suite* a duplicate is a resolve-time
  error), optional `name`/`description`, and a required, non-empty
  `steps` list.

## Steps

A step is one entry in a testcase's (or scenario's) `steps` list. There
are two shapes:

### Template-step: `client` + `template`

Sends a rendered [template](template.md) via a registered
[client](behaviours.md#clients):

```json
{
  "name": "POST /login",
  "client": "http",
  "template": "login_request",
  "dataset": { "data": { "username": "alice", "password": "secret" } },
  "save": [{ "path": "$.token", "as": "auth_token" }]
}
```

- **`name`** optional label shown in results. Defaults to
  `"<client>: <template name>"` if omitted.
- **`client`** required, name of a registered client (see
  [behaviours.md](behaviours.md#clients)). Must also appear in the
  template's own `clients` list.
- **`template`** required a file path (see [template.md](template.md))
  or an inline template body.
- **`dataset`** required a file path (see [dataset.md](dataset.md)) or
  an inline dataset body, filling in the template's `{{placeholder}}`s.
- **`assert`** optional list of checks run against the response. See
  [Assertions](#assertions) below.
- **`save`** optional list of values to extract from the response into
  named state later steps can reference via `{{placeholder}}`. See
  [Saving values for later steps](#saving-values-for-later-steps) below.

### Scenario-call: `scenario`

Runs a reusable [scenario](scenario.md)'s steps inline at this point:

```json
{
  "name": "login as each seeded user",
  "scenario": "login_and_get_token",
  "dataset": "seeded_users"
}
```

- **`name`** optional label shown in results. Defaults to the scenario's
  own name if omitted.
- **`scenario`** required a file path (see [scenario.md](scenario.md))
  or an inline scenario body.
- **`dataset`** optional input values passed to the scenario, merged
  with the scenario's own `default_dataset`. See
  [scenario.md](scenario.md#how-dataset-merges-with-default_dataset) for
  the exact merge rule. A scenario call has no `assert`/`save` of its own
  its *nested* steps carry those individually.

A scenario call has no single response of its own to assert against
only its nested steps do, so `assert` only ever appears on a
template-step, never on a scenario-call step.

## Data-driven steps (`rows`)

If a step's (or scenario call's) resolved `dataset` has `rows` instead of
`data`, that step runs **once per row**, producing one result per row:

```json
{
  "name": "create account for each seeded user",
  "client": "http",
  "template": "create_account_request",
  "dataset": "seeded_users",
  "assert": [
    { "expected": { "username": "{{username}}", "id": "$expected" } }
  ]
}
```

See [dataset.md](dataset.md#rows-data-driven-iteration) for how `rows`
datasets are defined.

## Assertions

`assert` is a list of checks run against a template-step's response after
it executes (once per row, if the dataset iterates):

```json
"assert": [
  { "path": "$.status", "expected": 200 },
  { "matcher": "json_schema_match", "path": "$.order", "expected": { "type": "object", "required": ["id"] } }
]
```

Each entry is dispatched by `matcher` name (defaults to `"json_match"` if
omitted) to a registered assertion matcher. Every assertion on a step runs
independently one failing doesn't stop the others from running, and
every result is reported. See [json_match.md](json_match.md) (the
default matcher) and [json_schema_match.md](json_schema_match.md) for
what each one can express, or [behaviours.md](behaviours.md#matchers) to
write your own.

## Saving values for later steps

`save` extracts a value from a step's response into named state that
**later steps in the same run** can reference via `{{placeholder}}`:

```json
{
  "client": "http",
  "template": "login_request",
  "dataset": "test_user",
  "save": [{ "path": "$.token", "as": "auth_token" }]
}
```

A later step can now use `{{auth_token}}` anywhere a template/dataset/
assertion would normally interpolate it:

```json
{
  "client": "http",
  "template": "get_profile_request",
  "dataset": { "data": { "auth_token": "{{auth_token}}" } }
}
```

- **`path`** required, a `$.a.b.c` path into the response (same syntax as
  [json_match's path](json_match.md#selecting-part-of-the-response)).
- **`as`** required, the name to save it under.

Extraction is best-effort: if `path` doesn't resolve against a given
response (e.g. an error response doesn't have the field a success
response would), that `save` entry is silently skipped rather than
failing the step a response's shape legitimately varies, so a missing
field to save isn't automatically a test failure the way a missing
`{{placeholder}}` at render time is.

## Inline scenarios and templates

Both `template` and `scenario` accept an inline body instead of a file
path, for one-off cases that don't need reuse:

```json
{
  "name": "inline template, no file needed",
  "client": "http",
  "template": {
    "clients": ["http"],
    "payload": { "foo": "{{foo}}" }
  },
  "dataset": { "data": { "foo": "bar" } }
}
```

```json
{
  "name": "inline scenario, no file needed",
  "scenario": {
    "steps": [{ "client": "http", "template": "login_request" }]
  },
  "dataset": { "data": { "username": "alice" } }
}
```

## Putting it together

```json
{
  "id": "checkout-flow",
  "name": "Checkout Flow",
  "description": "Verifies a logged-in user can add an item to the cart and pay successfully.",
  "tags": ["smoke", "checkout"],
  "testcases": [
    {
      "id": "add-to-cart-and-pay",
      "name": "Add to cart and pay",
      "steps": [
        {
          "scenario": "login_and_get_token",
          "dataset": { "data": { "username": "alice" } }
        },
        {
          "name": "POST /cart",
          "client": "http",
          "template": "add_to_cart_request",
          "dataset": { "data": { "sku": "ABC123", "qty": 1 } },
          "assert": [
            { "matcher": "json_match", "path": "$.total", "expected": 42 }
          ]
        }
      ]
    },
    {
      "id": "login-as-each-seeded-user",
      "name": "Login as each seeded user",
      "steps": [
        { "scenario": "login_and_get_token", "dataset": "seeded_users" }
      ]
    }
  ]
}
```

## See also

- [template.md](template.md) the message/payload a template-step sends.
- [dataset.md](dataset.md) where `{{placeholder}}` values come from,
  and how `rows` drives per-row iteration.
- [scenario.md](scenario.md) reusable step sequences called from a
  step's `scenario` field.
- [json_match.md](json_match.md) / [json_schema_match.md](json_schema_match.md) the built-in assertion matchers.
- [behaviours.md](behaviours.md) writing your own client/matcher/generator.
- [test_plan.md](test_plan.md) grouping several suites to run together.
- [maestro.md](maestro.md) actually running a suite and checking results.
