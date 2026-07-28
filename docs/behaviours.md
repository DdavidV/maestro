# Writing your own clients, matchers, and generators

Maestro ships built-in implementations of all three extension points this
page covers the `http` client ([http_client.md](http_client.md)), the
`json_match`/`json_schema_match` assertion matchers
([json_match.md](json_match.md), [json_schema_match.md](json_schema_match.md)),
and the `today` dataset generator (used from a
[dataset](dataset.md#values-that-cant-be-static-generated)). This page is
about writing your **own** a client for a protocol Maestro doesn't
support out of the box, a matcher for a check `json_match` can't express,
or a generator for test data that can't be written as a static literal.

All three follow the same core pattern: `use` a Maestro behaviour module
with a `name:` (clients/matchers) or no options at all (generators), and
Maestro discovers it automatically no explicit registration list to
maintain anywhere. Every example below has been checked against the
actual behaviour modules.

## Clients

A client is something that knows how to send a rendered
[template](template.md) through a protocol HTTP, Kafka, gRPC, raw TCP,
or anything else. `Maestro.Client` is the behaviour.

### Minimal example

```elixir
defmodule MyApp.Maestro.EchoClient do
  use Maestro.Client, name: "echo"

  @impl true
  def send(_call_state, rendered) do
    {:ok, %{"echoed" => rendered["payload"]}}
  end
end
```

`use Maestro.Client, name: "echo"` is enough for this module to be
discovered and registered under the name `"echo"` reference it from a
step's `client` field, and pair it with a template whose `clients` list
includes `"echo"`:

```json
{
  "client": "echo",
  "template": { "clients": ["echo"], "payload": { "hello": "{{name}}" } },
  "dataset": { "data": { "name": "world" } }
}
```

### The three callbacks

```elixir
@callback name() :: String.t()
@callback init_client() :: {:ok, client_state :: term} | {:error, term}
@callback init(client_state :: term, rendered) :: {:ok, call_state :: term} | {:error, term}
@callback send(call_state :: term, rendered) :: {:ok, response :: term} | {:error, term}
```

`name/0` is filled in automatically by `use Maestro.Client, name: "..."`
you never implement it yourself. `send/2` is the only one you're
required to implement. `init_client/0` and `init/2` are both optional:

- **`init_client/0`** called **once ever**, the first time this client
  is discovered (at application boot, or whenever
  `Maestro.Client.Registry.load!/0` runs). This is where you set up
  infrastructure the client needs regardless of any particular step
  starting a supervised connection pool, opening a database connection
  not per-call configuration. Its result (`client_state`) is memoized for
  the application's lifetime.
- **`init/2`** called **once per step execution**, right before
  `send/2`. Receives the memoized `client_state` and the step's
  `rendered` template (`payload`/`options`, with every `{{placeholder}}`
  already filled in). This is where per-call configuration lives it
  comes from the step's own `options`. Returns a `call_state` that
  `send/2` will use.
- **`send/2`** called once per step execution, immediately after
  `init/2`. Receives `call_state` and the same `rendered` template
  `init/2` saw, and actually performs the send.

If you skip `init_client/0`/`init/2` entirely, `call_state` just defaults
to whatever `client_state` was (`nil` if you skipped `init_client/0`
too).

### A client with real setup and per-call state

```elixir
defmodule MyApp.Maestro.QueueClient do
  use Maestro.Client, name: "queue"

  @impl true
  def init_client do
    case MyApp.Queue.Pool.start_link(size: 5) do
      {:ok, pid} -> {:ok, %{pool: pid}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def init(%{pool: pool}, rendered) do
    queue_name = rendered["options"]["queue"]
    {:ok, %{pool: pool, queue_name: queue_name}}
  end

  @impl true
  def send(%{pool: pool, queue_name: queue_name}, rendered) do
    MyApp.Queue.publish(pool, queue_name, rendered["payload"])
  end
end
```

```json
{
  "clients": ["queue"],
  "options": { "queue": "orders" },
  "payload": { "order_id": "{{order_id}}" }
}
```

### Failure handling

`init_client/0`/`init/2`/`send/2` all return `{:error, reason}` on
failure, or can simply raise either way it's caught and reported as a
structured `Maestro.Client.Error`, never a crash that takes down the
whole run. A client whose `init_client/0` fails doesn't take the
registry down: every *other* client still registers and works normally;
only this one client returns `{:error, {:init_failed, reason}}` when
looked up.

## Matchers

A matcher checks an [assertion](suite.md#assertions) entry against a
step's response. `Maestro.Assert.Matcher` is the behaviour. Unlike
clients, matchers have no one-time setup a matcher is expected to be
static, stateless code.

### Minimal example

```elixir
defmodule MyApp.Maestro.WithinLastHour do
  use Maestro.Assert.Matcher, name: "within_last_hour"

  alias Maestro.Assert.Reason

  @impl true
  def match(assertion, actual, _context) do
    {:ok, timestamp, _offset} = DateTime.from_iso8601(actual)

    if DateTime.diff(DateTime.utc_now(), timestamp, :second) <= 3600 do
      :ok
    else
      {:error, [Reason.new(:not_within_last_hour, assertion.expected, actual)]}
    end
  end
end
```

```json
{ "matcher": "within_last_hour", "path": "$.created_at", "expected": null }
```

### The callback

```elixir
@callback name() :: String.t()
@callback match(assertion :: Maestro.assertion(), actual :: term, context :: Maestro.Core.Interpolation.context()) ::
            :ok | {:error, [Maestro.Assert.Reason.t()]}
```

- **`assertion`** the whole atomized assertion entry (`:matcher`,
  `:path`, `:expected`, plus any matcher-specific fields you added see
  [Matcher-specific fields](#matcher-specific-fields) below), as written
  in the suite.
- **`actual`** the step's response (or whatever `path`, if your matcher
  honors one, selected out of it `path`/selection is entirely your
  matcher's own concern, `Maestro.Assert.Matcher` doesn't do any of that
  for you).
- **`context`** the same interpolation context (dataset fields merged
  with accumulated `save` state) the step's own template rendered
  against, in case your matcher needs to reference it (e.g. to compare
  against a `{{saved_value}}`).

Return `:ok` on a pass. Return `{:error, reasons}` on a fail, where
`reasons` is a **non-empty list** of `Maestro.Assert.Reason.t()` one
entry per distinct problem found. If your matcher can only ever find one
problem per call, return a single-element list; if it can find several
independent problems in one pass (the way `json_match` checks every
field of an object and reports every mismatch, not just the first),
report all of them.

### `assertion.expected`/fields aren't pre-interpolated for you

A matcher's own fields (`expected`, or anything matcher-specific) are
**not** interpolated automatically before `match/3` is called they're
opaque to everything except the matcher that owns them, the same way a
template's `payload`/`options` are opaque to everything except the
client that sends them. If your matcher wants `{{placeholder}}` support
in `expected` (most do), render it yourself:

```elixir
defmodule MyApp.Maestro.WithinLastHour do
  use Maestro.Assert.Matcher, name: "within_last_hour"

  alias Maestro.Assert.Reason
  alias Maestro.Core.Interpolation

  @impl true
  def match(assertion, actual, context) do
    with {:ok, expected} <- Interpolation.render(assertion.expected, context) do
      # ...compare actual against the now-interpolated expected...
      :ok
    end
  end
end
```

The built-in `Maestro.Matchers.JsonMatch` interpolates `expected` but
deliberately *not* `path` each matcher decides what inside its own
fields needs templating and when.

### Matcher-specific fields

An assertion entry can carry fields beyond `matcher`/`path`/`expected`
they pass through untouched to your matcher:

```json
{ "matcher": "within_last_hour", "path": "$.created_at", "expected": null, "tolerance_seconds": 120 }
```

```elixir
def match(%{tolerance_seconds: tolerance} = assertion, actual, _context) do
  # ...
end
```

### `Maestro.Assert.Reason`

```elixir
%Maestro.Assert.Reason{reason: :not_within_last_hour, expected: nil, actual: "2020-01-01T00:00:00Z", path: nil}
```

- **`reason`** required, a short machine-readable atom naming the kind of
  mismatch (`:not_equal`, `:length_mismatch`, your own
  `:not_within_last_hour`, ...).
- **`expected`**/**`actual`** the specific values that differed for a
  mismatch nested inside a larger structure, these are the nested
  sub-values, not necessarily the assertion's whole `expected`/response.
- **`path`** where inside the checked value this problem was found (e.g.
  `"$.items[2].id"`), `nil` if there's nothing to descend into.

### Failure handling

A matcher that raises is caught and reported the same as any other
assertion failure it never crashes the run.

## Generators

A generator produces a value at **render time** for a
`{"$generated": ...}` marker inside a [dataset](dataset.md)'s `data`/
`rows` bag for values that can't be written as a static literal (a
random/unique id, an environment-derived config value, anything computed
fresh per use). `Maestro.Generator` is the module you `use`; unlike
clients/matchers, there's no `name:` option one module can define
*several* named generators, each its own `generated_data` block.

### Minimal example

```elixir
defmodule MyApp.Maestro.Generators do
  use Maestro.Generator

  generated_data "order_id", _args, _context do
    {:ok, "ORD-" <> (:crypto.strong_rand_bytes(4) |> Base.encode16())}
  end
end
```

```json
{
  "data": {
    "order_id": { "$generated": "order_id" },
    "sku": "ABC123"
  }
}
```

`order_id` resolves to a fresh value **every time this dataset is
rendered** once per step execution, or once per row for a `rows`
dataset (see [dataset.md](dataset.md#values-that-cant-be-static-generated)),
never cached across a run.

### `generated_data name, args_pattern, context_pattern do ... end`

```elixir
generated_data "name", args_pattern, context_pattern do
  # ...
  {:ok, value}
end
```

- **`name`** a string, the name suite authors reference via
  `{"$generated": "name"}` or `{"$generated": {"name": "name", "args": [...]}}`.
- **`args_pattern`** an ordinary function-head pattern, matched against
  whatever `args` the caller passed (already interpolated against
  `context` a `{{placeholder}}` inside `args` is resolved before your
  generator ever sees it, same as `json_match`'s `$mfa` args).
- **`context_pattern`** an ordinary function-head pattern, matched
  against the same interpolation context (dataset fields merged with
  accumulated `save` state) `{{placeholder}}` rendering already has so
  a generator can, for example, read a value an earlier step `save`d.

A block returns `{:ok, value}` (spliced directly into the dataset tree in
place of the marker) or `{:error, reason}` a raise is also caught and
reported the same way, so a broken generator can't crash a run.

### Grouping several generators in one module

One module can define as many `generated_data` blocks as makes sense
useful for a family of related values, e.g. every environment-derived
config value your suites need:

```elixir
defmodule MyApp.Maestro.Generators do
  use Maestro.Generator

  generated_data "order_id", _args, _context do
    {:ok, "ORD-" <> (:crypto.strong_rand_bytes(4) |> Base.encode16())}
  end

  generated_data "env_var", [var_name], _context do
    case System.fetch_env(var_name) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:env_var_not_set, var_name}}
    end
  end
end
```

```json
{
  "data": {
    "order_id": { "$generated": "order_id" },
    "api_base_url": { "$generated": { "name": "env_var", "args": ["API_BASE_URL"] } }
  }
}
```

Each `generated_data` block registers exactly one name; each name must be
unique **within a module** reusing a name in the same module is a
compile error, not a silent shadow. A name registered by two *different*
modules is a separate, looser concern: Maestro logs a warning (since
which module wins is not something you control or should rely on being
stable), rather than silently picking one rename one of them if you see
that warning.

### Referencing a saved value from a generator

Since a generator receives the same `context` interpolation already has,
it can react to state an earlier step `save`d:

```elixir
generated_data "next_page_offset", [], context do
  case context do
    %{"last_seen_id" => last_id} -> {:ok, last_id + 1}
    _ -> {:ok, 0}
  end
end
```

### The raw-MFA escape hatch

If you don't want a registered name at all for a one-off, or when you'd
rather the suite file be maximally explicit about exactly which function
runs skip `Maestro.Generator` entirely and call any already-loaded
function directly:

```json
{
  "data": {
    "order_id": {
      "$generated": {
        "module": "MyApp.Maestro.Generators",
        "function": "raw_order_id",
        "args": []
      }
    }
  }
}
```

This bypasses the generator registry and calls
`MyApp.Maestro.Generators.raw_order_id(...args)` directly (via
`Maestro.Core.SafeMFA`, the same mechanism `json_match`'s `$mfa` uses).
The function doesn't need `use Maestro.Generator` at all for this form
any exported function works. See
[dataset.md](dataset.md#values-that-cant-be-static-generated) for the
full set of `$generated` shapes.

## See also

- [dataset.md](dataset.md) where `$generated` markers are used.
- [suite.md](suite.md#assertions) where `assert`/matcher entries are used.
- [template.md](template.md) what a client sends.
- [http_client.md](http_client.md) the built-in `http` client, as a
  fully worked real-world example.
- [json_match.md](json_match.md) / [json_schema_match.md](json_schema_match.md) the built-in matchers.
