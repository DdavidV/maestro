# `json_schema_match`: validate a response against a JSON Schema

`json_schema_match` is a built-in assertion matcher that checks a step's
response (or a `path`-selected part of it) against a JSON Schema, instead of
against an exact expected value/shape. Use it when you care about a
*contract* types, required fields, enums, numeric ranges, string formats
rather than pinning specific values. For pinning specific values, see
[`json_match`](json_match.md) (the default matcher).

Every example below is a complete `assert` entry as it would appear in a
step, and every example has been checked against the actual matcher
behavior.

## The shape of an assertion entry

```json
{
  "matcher": "json_schema_match",
  "path": "$.order",
  "expected": {
    "type": "object",
    "required": ["id", "status"],
    "properties": {
      "id": { "type": "integer" },
      "status": { "type": "string", "enum": ["pending", "confirmed"] }
    }
  }
}
```

- **`matcher`** required here you must explicitly write `"json_schema_match"`,
  since the default matcher is `json_match`.
- **`path`** optional. Selects a sub-value of the step's response to
  validate, using the same `$.a.b.c` path syntax `json_match` uses. If
  omitted, the *whole* response is validated.
- **`expected`** required. A JSON Schema document (draft-07). The response
  (or the value at `path`) is validated against it: the assertion passes if
  and only if the value conforms to the schema.

A step can mix `json_schema_match` with `json_match` (or any other matcher)
freely, one assertion per entry:

```json
"assert": [
  { "matcher": "json_schema_match", "path": "$.order", "expected": { "type": "object", "required": ["id"] } },
  { "path": "$.order.status", "expected": "confirmed" }
]
```

## Templating

`expected` (the schema itself) is rendered through `{{placeholder}}`
templating against the step's dataset fields or previously `save`d values,
exactly like `json_match`'s `expected`, before it's used to validate:

```json
{
  "matcher": "json_schema_match",
  "path": "$.status",
  "expected": { "type": "string", "enum": ["{{allowed_status}}"] }
}
```

This resolves before validation happens, so it works at any depth in the
schema. A `{{placeholder}}` referencing a value that isn't in the
dataset/saved state is a hard error (the assertion fails, it doesn't
silently pass or validate against a literal `"{{...}}"` string).

## What passes and what fails

Any value JSON Schema can express is fair game: types, `required`,
`enum`, `minItems`/`maxItems`, `minimum`/`maximum`, `pattern`,
`additionalProperties`, nested `properties`/`items`, and so on standard
draft-07 JSON Schema, nothing Maestro-specific.

```json
{ "matcher": "json_schema_match", "expected": { "type": "array", "items": { "type": "integer" }, "minItems": 1 } }
```

Passes against `[1, 2, 3]`. Fails against `[]` (violates `minItems`) or
`[1, "two"]` (the second element isn't an integer).

By default, object schemas are open extra properties not listed under
`properties` are allowed, same as plain JSON Schema semantics. Add
`"additionalProperties": false` to the schema itself to close it:

```json
{
  "matcher": "json_schema_match",
  "expected": {
    "type": "object",
    "properties": { "id": { "type": "integer" } },
    "additionalProperties": false
  }
}
```

This fails if the response has any field other than `id`.

A validation failure reports one problem per schema-validation error found
not just the first: a response violating several parts of the schema at
once (a wrong type on one field, a missing required property, an enum
violation on another) gets every one of them back together, each with its
own `path` pointing at exactly where in the checked value it went wrong
(e.g. `"#/status"`).

## A malformed schema is a normal failure, not a crash

If `expected` itself isn't a valid JSON Schema (a typo like
`"type": "sting"`, or `expected` not being an object at all), the assertion
fails as a normal, reported problem rather than crashing the test run:

```json
{ "matcher": "json_schema_match", "expected": { "type": "sting" } }
```

## Selecting part of the response

Same `path` syntax as `json_match` (see
[Selecting part of the response](json_match.md#selecting-part-of-the-response)):

```json
{
  "matcher": "json_schema_match",
  "path": "$.data.items.0",
  "expected": { "type": "object", "required": ["id"] }
}
```

Validates just the first element of `response.data.items` against the
schema, rather than the whole response.

## When to use this instead of `json_match`

`json_match` pins exact expected values (with escape hatches like
`$expected`/`$regex` for "don't check the value, but check something about
it"). `json_schema_match` is the better fit when:

- You want to assert a *contract* ("`status` is one of these three
  strings", "`items` is a non-empty array of objects each shaped like
  X") without listing every field's exact value.
- You already have (or want to maintain) a JSON Schema for a response type
  reused across several assertions or suites just reference/paste the same
  schema.
- You want `additionalProperties: false`-style closed-object checking mixed
  with open per-field type/format checks in one document, rather than
  `json_match`'s field-by-field `$_`/`$expected` directives.

They compose fine as separate `assert` entries on the same step when you
want both: a `json_schema_match` for the overall contract and a `json_match`
pinning one or two specific values you do care about exactly.
