# `json_match`: structural JSON assertions

`json_match` is Maestro's built-in assertion matcher a KATT-inspired engine
for checking a step's response against an expected JSON shape. It's the
default matcher: if a step's `assert` entry doesn't name one, `json_match` is
used automatically. For checking a response against a JSON Schema contract
instead of exact values, see [`json_schema_match`](json_schema_match.md).

Every example below is a complete `assert` entry as it would appear in a
step, and every example has been checked against the actual matcher
behavior.

## The shape of an assertion entry

```json
{
  "matcher": "json_match",
  "path": "$.total",
  "expected": 42
}
```

- **`matcher`** optional, defaults to `"json_match"`. You only need this
  field if you're using a different, custom-registered matcher.
- **`path`** optional. Selects a sub-value of the step's response to check,
  using a small `$.a.b.c` path syntax (see [Selecting part of the response](#selecting-part-of-the-response)
  below). If omitted, the *whole* response is checked.
- **`expected`** required. The shape you're asserting the response (or the
  value at `path`) looks like. This is where everything below happens.

A step can have more than one assertion:

```json
"assert": [
  { "path": "$.status", "expected": "ok" },
  { "path": "$.total", "expected": 42 }
]
```

Each one is checked independently, if any of them fails, the step is
recorded as failed, but every assertion still runs and its own pass/fail
result is reported (checking assertion #2 doesn't stop just because #1
failed).

## Templating

`expected` can reference the step's dataset fields or previously `save`d
values with `{{placeholder}}`, exactly like a template's `payload`:

```json
{ "path": "$.order_id", "expected": "{{order_id}}" }
```

This resolves *before* anything below is interpreted, so it works at any
depth inside an object, inside a list, inside a `$contains`/`$excludes`
list, inside `$mfa` args. A `{{placeholder}}` referencing a value that isn't
in the dataset/saved state is a hard error (the assertion fails, it doesn't
silently pass).

## Matching a plain value

If `expected` isn't an object or a list, it's a plain equality check:

```json
{ "path": "$.status", "expected": "ok" }
```

Passes only if the response's `status` field is exactly the string `"ok"`.
Works for numbers, booleans, and `null` too.

## Matching an object

By default, object matching is **open**: every field you list in `expected`
must match, but the response is allowed to have *other* fields you didn't
mention.

```json
{
  "expected": {
    "id": 123,
    "status": "ok"
  }
}
```

This passes against `{"id": 123, "status": "ok", "created_at": "2026-01-01"}` `created_at` is simply ignored, since it wasn't mentioned.

### Asserting a field exists (without checking its value)

```json
{ "expected": { "token": "$expected" } }
```

Passes as long as the response has a `token` field, no matter what its value
is (including `null`). Fails if `token` is missing entirely.

### Asserting a field does *not* exist

```json
{ "expected": { "internal_debug_info": "$unexpected" } }
```

Passes as long as the response has **no** `internal_debug_info` field at
all. Fails if that key is present, even if its value is `null`.

### Asserting there are no *other* fields

Object matching is open by default (extra fields are ignored). To make it
**closed** reject anything you didn't explicitly list add a `"$_"` key
mapped to `"$unexpected"`:

```json
{
  "expected": {
    "id": 123,
    "status": "ok",
    "$_": "$unexpected"
  }
}
```

This now only passes if the response has *exactly* `id` and `status`, no
other fields. If it has anything else (`created_at`, say), the assertion
fails and reports which extra fields were found.

`"$_"` mapped to anything other than `"$unexpected"` is a mistake Maestro
catches for you the assertion fails immediately with a clear error rather
than silently doing nothing.

Closing applies wherever you put it, not just at the top level:

```json
{
  "expected": {
    "user": {
      "id": 1,
      "$_": "$unexpected"
    }
  }
}
```

Here the *outer* object can still have any other fields alongside `user` only `user` itself is closed.

## Matching a list

### Ordered (the default)

A plain JSON array means **exact order, exact length**:

```json
{ "expected": [1, 2, 3] }
```

Only passes against exactly `[1, 2, 3]` `[1, 3, 2]` (wrong order) and
`[1, 2, 3, 4]` (extra element) both fail.

You can use `"$expected"` inside an ordered list as a positional wildcard
"there must be something here, I don't care what":

```json
{ "expected": [1, "$expected", 3] }
```

Passes against `[1, 2, 3]`, `[1, "anything", 3]`, `[1, {"nested": true}, 3]` the middle element is never checked, but it must exist and the list must
still be exactly 3 elements long.

`"$unexpected"` can appear as the **last** element of an ordered list,
meaning "the list ends here":

```json
{ "expected": ["$expected", 2, "$expected", 4, "$unexpected"] }
```

Against `[1, 2, 3, 4]`: position 0 is a wildcard (matches `1`), position 1
must be `2`, position 2 is a wildcard (matches `3`), position 3 must be `4`,
and `"$unexpected"` confirms there's nothing at position 4 or beyond the
list must have exactly 4 elements. `"$unexpected"` anywhere *except* the
last position is rejected outright (a position can't simultaneously "not
exist" while later positions require elements after it).

### Unordered subset `$contains`

Sometimes you only care that a few specific items are *somewhere* in a
list, in any order, and don't want to hard-code the list's exact contents:

```json
{
  "expected": {
    "$contains": ["smoke", "checkout"]
  }
}
```

Passes against `["nightly", "smoke", "checkout"]` order doesn't matter,
and extra elements (`"nightly"`) are fine. Items can be objects too, and can
use `$expected`/`$unexpected` themselves:

```json
{
  "expected": {
    "$contains": [
      { "sku": "ABC123", "qty": "$expected" }
    ]
  }
}
```

**One limitation worth knowing about**: matching is greedy, not a full
solve-every-possibility search. If two wanted items *could* both match the
same element, but only in one specific pairing does everything work out,
`$contains` isn't guaranteed to find that pairing it tries wanted items in
the order you wrote them, and locks in the first match it finds. In
practice this essentially never matters (it only bites when your wanted
items are ambiguous with each other), but if you hit a `$contains` that
"should" pass and doesn't, this is the first thing to check.

### Unordered non-membership `$excludes`

The opposite of `$contains`: none of the listed items may appear anywhere
in the list.

```json
{
  "expected": {
    "$excludes": [{ "status": "cancelled" }]
  }
}
```

Passes as long as no element of the response list deep-matches
`{"status": "cancelled"}`. Unlike `$contains`, there's no greedy/ordering
subtlety here each excluded item is independently checked against every
element.

### Length `$length`

Checks how many elements a list has, without checking the elements
themselves. Four forms:

```json
{ "expected": { "$length": 3 } }
```

Exact length: the list must have precisely 3 elements.

```json
{ "expected": { "items": { "$length": { "$gt": 0 } } } }
```

`$gt`/`$lt` strictly greater than / strictly less than:

```json
{ "expected": { "items": { "$length": { "$lt": 100 } } } }
```

```json
{ "expected": { "items": { "$length": { "$between": [1, 10] } } } }
```

`$between` inclusive on both ends: a list of exactly 1 or exactly 10
elements both pass.

**`$length` can't be combined with `$contains`/`$excludes` in the same
object** `{"$length": 3, "$contains": [1]}` is *not* "length 3 and
contains 1," it's an invalid combination (a wrapper object is only
recognized as a directive when it has exactly one key, with two keys it's
treated as a literal object to match, which then fails outright since the
response is a list, not an object). To check both length and contents of
the same list, use two separate `assert` entries with the same `path`:

```json
"assert": [
  { "path": "$.items", "expected": { "$length": { "$between": [1, 5] } } },
  { "path": "$.items", "expected": { "$contains": ["required-item"] } }
]
```

## Regex matching

```json
{ "expected": { "order_id": { "$regex": "^ORD-\\d+$" } } }
```

`actual` must be a string matching the given pattern (standard regex
syntax). Only makes sense against string values a `$regex` check against
a number or object fails cleanly rather than crashing.

## Running custom code `$mfa`

For checks that can't be expressed declaratively, `$mfa` calls an
already-loaded Elixir function of your choosing:

```json
{
  "expected": {
    "created_at": {
      "$mfa": {
        "module": "MyApp.Checks",
        "function": "within_last_hour",
        "args": []
      }
    }
  }
}
```

This calls `MyApp.Checks.within_last_hour(actual_value, ...args)` the
value being checked is always the first argument, followed by whatever you
put in `args` (which can itself use `{{placeholders}}`, resolved before the
call). The function should return:

- `true` or `:ok` the check passes
- `false` the check fails
- `{:error, reason}` the check fails, `reason` shows up in the report

**This runs real code from your suite file.** That's the point (it's the
escape hatch for anything the declarative directives can't express), but it
means `$mfa` should only reference functions you trust, the same way you'd
only register clients or custom matchers you trust. A bad module/function
name, a wrong arity, or the function raising never crashes the test run
it just fails that one assertion with a clear reason.

## Selecting part of the response

By default, `expected` is checked against the *entire* response. Use `path`
to check just one part of it:

```json
{ "path": "$.data.items.0.id", "expected": 42 }
```

Path syntax: `$.` followed by dot-separated segments. Each segment either
looks up a key in an object (`$.data`) or, if the current value is a list,
indexes into it by position, **counting from 0** (`$.items.0` is the list's
*first* element, `$.items.1` is the second, and so on). If any segment
doesn't resolve a missing key, an out-of-range index, or stepping into a
value that's neither an object nor a list the assertion fails and reports
exactly where it went wrong.

## Putting it together

A more realistic example, combining several of the above against a
checkout API response:

```json
{
  "path": "$.order",
  "expected": {
    "id": "$expected",
    "status": "confirmed",
    "customer_id": "{{customer_id}}",
    "items": {
      "$contains": [
        { "sku": "ABC123", "qty": 2 }
      ]
    },
    "tags": {
      "$excludes": ["cancelled", "refunded"]
    },
    "confirmation_code": { "$regex": "^CONF-[A-Z0-9]{6}$" },
    "internal_notes": "$unexpected"
  }
}
```

This says: look at `response.order`, assert it has *some* `id` (don't care
what), `status` is exactly `"confirmed"`, `customer_id` matches whatever
`{{customer_id}}` resolves to from the dataset, the `items` list contains
(somewhere, in any order) an item with `sku: "ABC123"` and `qty: 2`, the
`tags` list contains neither `"cancelled"` nor `"refunded"`,
`confirmation_code` matches the given pattern, and there is **no**
`internal_notes` field on the order at all. Every other field on `order`
(there might be many) is simply ignored, since the object isn't closed with
`$_`.
