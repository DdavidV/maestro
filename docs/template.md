# Templates: reusable message/payload shapes

A template is the reusable shape of a message or request sent by a
[client](behaviours.md#clients) — the request body, headers, topic, or
whatever else that client needs — with `{{placeholder}}`s filled in from
a [dataset](dataset.md) at render time. Defining a request shape once as a
template avoids repeating the same JSON/options structure across every
step that sends it.

Every example below is a complete template file as it would appear under
`<resource_dir>/templates/`, and every example has been checked against
the actual schema/resolver behavior.

## Where a template file lives

`<resource_dir>/templates/<path>.json` — see [maestro.md](maestro.md) for
what `resource_dir` is. A [step](suite.md#steps) references a template by
`<path>`, extension-less:

```json
{ "client": "http", "template": "login_request", "dataset": "test_user" }
```

resolves `<resource_dir>/templates/login_request.json`. Like datasets and
scenarios, a template can also be written **inline** in place of that
path string — see [Inline vs. file-based](#inline-vs-file-based) below.

## The shape of a template

```json
{
  "name": "create_order_request",
  "description": "HTTP request to create an order.",
  "clients": ["http"],
  "options": {
    "method": "POST",
    "url": "https://shop.example.com/orders/{{order_id}}",
    "headers": { "Authorization": "Bearer {{auth_token}}" }
  },
  "payload": {
    "sku": "{{sku}}",
    "qty": "{{qty}}"
  }
}
```

- **`name`** optional, cosmetic display label shown in results/UI.
- **`description`** optional free-text description of what this template
  represents.
- **`clients`** required, non-empty list of registered client names this
  template is valid for (e.g. `["http"]`, `["kafka"]`). A step must pair
  this template with one of these clients — see
  [suite.md](suite.md#steps).
- **`payload`** required. The message/payload content itself — an object
  for structured payloads (JSON, gRPC message maps, ...), or a string for
  raw/text payloads. See [Payload shape](#payload-shape) below.
- **`options`** optional, defaults to `{}`. Client-specific configuration
  for *sending* the payload (URL/method/headers for `http`, topic/key for
  Kafka, host/port for raw TCP, ...). The shape of `options` is defined
  entirely by the client itself, not by this schema — see that client's
  own docs (e.g. [http_client.md](http_client.md)) for what it expects.

Both `payload` and `options` are rendered through `{{placeholder}}`
templating against the step's resolved dataset/saved state at render
time — the *same* rendering pass, so a placeholder can appear in either
one.

## Payload shape

A **map** payload is the common case for a structured message:

```json
{
  "clients": ["http"],
  "options": { "method": "POST", "url": "https://api.example.com/orders" },
  "payload": { "sku": "{{sku}}", "qty": "{{qty}}" }
}
```

A **string** payload sends raw/text content instead — useful for
non-JSON protocols:

```json
{
  "name": "heartbeat_frame_v1",
  "description": "Raw TCP heartbeat frame: pipe-delimited fields terminated with CRLF.",
  "clients": ["tcp"],
  "options": { "host": "gateway.example.com", "port": 9000 },
  "payload": "HB|{{device_id}}|{{sequence}}\r\n"
}
```

A whole-string placeholder (the entire payload is just `"{{foo}}"`, nothing
else) preserves the dataset value's original type — e.g. `"qty":
"{{qty}}"` against `{"qty": 1}` renders `"qty": 1`, an integer, not the
string `"1"`. A placeholder embedded inside a larger string (`"Bearer
{{auth_token}}"`) always stringifies and concatenates, since a mixed
string has nowhere else to put a non-string type. This is the same
rendering rule everywhere `{{placeholder}}` appears in Maestro — datasets,
templates, assertions — not just here.

## Client-specific `options`

`options`'s fields are entirely up to the client named in `clients` — this
schema doesn't constrain them at all. For the built-in `http` client, see
[http_client.md](http_client.md) for the full set (`method`, `url`,
`headers`, `query`, `timeout`, `transport_mfa`). A custom client you write
yourself defines its own `options` shape — document it the same way.

## Inline vs. file-based

Anywhere a template is referenced (a step's `template`), you can write
the template body directly instead of a file path string:

```json
{
  "client": "http",
  "template": {
    "clients": ["http"],
    "payload": { "foo": "{{foo}}" }
  },
  "dataset": { "data": { "foo": "bar" } }
}
```

Useful for a one-off request that doesn't need reuse across steps.

## Examples

A Kafka message:

```json
{
  "name": "order_created_v1",
  "description": "Kafka message for OrderCreated events.",
  "clients": ["kafka"],
  "options": {
    "topic": "orders.created",
    "key": "{{order_id}}"
  },
  "payload": {
    "event": "order_created",
    "order_id": "{{order_id}}",
    "total": "{{total}}"
  }
}
```

An HTTP request:

```json
{
  "name": "create_order_request",
  "description": "HTTP request to create an order.",
  "clients": ["http"],
  "options": {
    "method": "POST",
    "url": "https://shop.example.com/orders/{{order_id}}",
    "headers": { "Authorization": "Bearer {{auth_token}}" }
  },
  "payload": {
    "foo": "{{foo}}",
    "bar": "{{bar}}"
  }
}
```

A raw TCP frame:

```json
{
  "name": "heartbeat_frame_v1",
  "description": "Raw TCP heartbeat frame: pipe-delimited fields terminated with CRLF.",
  "clients": ["tcp"],
  "options": {
    "host": "gateway.example.com",
    "port": 9000
  },
  "payload": "HB|{{device_id}}|{{sequence}}\r\n"
}
```

## See also

- [dataset.md](dataset.md) — where `{{placeholder}}` values come from.
- [suite.md](suite.md#steps) — how a template is paired with a client and
  a dataset to actually run.
- [http_client.md](http_client.md) — the built-in `http` client's
  `options`/response shape.
- [behaviours.md](behaviours.md#clients) — writing your own client for a
  protocol Maestro doesn't ship built in.
