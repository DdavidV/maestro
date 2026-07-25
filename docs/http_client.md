# The `http` client

`http` is Maestro's built-in client for sending HTTP/HTTPS requests,
registered under the name `"http"`. It's backed by [`Req`](https://hexdocs.pm/req)
and a supervised connection pool started once at application boot.

Every example below is a complete template as it would appear in a step
(or a reusable template file), and every example has been checked against
the actual client behavior.

## Connection pool configuration

Every request goes through one shared [`Finch`](https://hexdocs.pm/finch)
connection pool. A local/sandboxed environment is fine with Finch's own
defaults (one pool, 50 connections), but a real test environment often
needs more headroom, or a dedicated pool per slow/high-latency host. Set
`config :maestro, :http_pool_options` (a keyword list passed straight
through to `Finch.start_link/1`, `:name` is always set by Maestro and
can't be overridden):

```elixir
config :maestro, :http_pool_options,
  pools: %{
    default: [size: 50, count: 4],
    "https://slow-legacy-service.example.com" => [size: 4, count: 1]
  }
```

See `Finch.start_link/1`'s own documentation for every available option
(pool size/count, protocol, connection options, ...).

## The shape of a template

```json
{
  "clients": ["http"],
  "options": {
    "method": "POST",
    "url": "https://shop.example.com/orders/{{order_id}}",
    "headers": { "Authorization": "Bearer {{auth_token}}" },
    "query": { "expand": "items" },
    "timeout": 5000
  },
  "payload": {
    "foo": "{{foo}}"
  }
}
```

`options` (all fields optional except `url`) and `payload` are both rendered
through `{{placeholder}}` templating against the step's dataset/saved state
first, same as every other client.

- **`method`** defaults to `"GET"`. Case-insensitive `"post"` and `"POST"`
  both work.
- **`url`** required. Must resolve to an absolute `http://` or `https://`
  URL after templating a relative URL, a typo, or a `{{placeholder}}` that
  didn't resolve into something URL-shaped is a hard assertion-independent
  step failure (`{:error, {:invalid_url, url}}`), not a silent no-op.
- **`headers`** defaults to `%{}`. A flat map of header name to value.
- **`query`** optional. A flat map of query-string parameters, appended to
  `url`.
- **`timeout`** milliseconds, defaults to `5000`. Caps the whole request
  (connecting, sending, and receiving the response).
- **`payload`** the request body. See below.
- **`transport_mfa`** optional escape hatch for proxies, TLS, and anything
  else the fields above don't cover. See [Configuring the transport](#configuring-the-transport-proxies-tls-and-more).

## Request body

- A **map** `payload` (the common case for a JSON API) is encoded as JSON.
  `content-type: application/json` is set automatically, unless `headers`
  already specifies a `content-type` (case-insensitively) explicitly, in
  which case yours is respected as-is.
- An **empty map** `{}` (what a template has if it omits `payload`
  entirely) sends no body at all not even an empty JSON object.
- A **string** `payload` is sent exactly as given, letting you send raw
  text, XML, form-encoded bodies, or anything else that isn't JSON.

```json
{ "clients": ["http"], "options": { "method": "POST", "url": "https://api.example.com/orders" }, "payload": { "sku": "ABC123", "qty": 2 } }
```

Sends `{"sku":"ABC123","qty":2}` as the body with `content-type:
application/json`.

## Response shape

A step's `response` (what `save`/`assert` see) looks like:

```json
{
  "status": 200,
  "headers": { "content-type": ["application/json"], "...": ["..."] },
  "body": { "...": "..." }
}
```

- **`status`** the HTTP status code, as an integer.
- **`headers`** every response header, grouped by name into a list of
  values (HTTP allows a header to appear more than once, so this is always
  a list even when there was only one value). Header names are lowercase.
- **`body`** JSON-decoded into a map/list automatically whenever the
  response's `content-type` says `application/json`, so `path`-based
  assertions can dig straight into it (`$.body.order.id`, for
  `json_match`/`json_schema_match`). Any other content type is left as the
  raw response body string.

This means a typical assertion looks like:

```json
"assert": [
  { "path": "$.status", "expected": 200 },
  { "path": "$.body.order_id", "expected": "{{order_id}}" }
]
```

## Configuring the transport: proxies, TLS, and more

`method`/`url`/`headers`/`query`/`timeout` cover the common case, but a real
test environment often needs more: routing through a corporate proxy,
trusting a self-signed staging certificate, presenting a client TLS cert, or
some other connection-level concern. Maestro doesn't try to model every
option [`Req`](https://hexdocs.pm/req)/[`Finch`](https://hexdocs.pm/finch)/[`Mint`](https://hexdocs.pm/mint)
expose that list is long and keeps growing. Instead, `transport_mfa` names
an already-loaded function of your own that receives the in-progress
`Req.Request` and returns a (possibly modified) one:

```json
{
  "clients": ["http"],
  "options": {
    "url": "https://internal-staging.example.com/orders",
    "transport_mfa": {
      "module": "MyApp.Maestro.Transport",
      "function": "via_corp_proxy",
      "args": ["{{proxy_host}}", 8080]
    }
  },
  "payload": {}
}
```

```elixir
defmodule MyApp.Maestro.Transport do
  def via_corp_proxy(%Req.Request{} = req, proxy_host, proxy_port) do
    req
    |> Req.Request.delete_option(:finch)
    |> Req.merge(connect_options: [proxy: {:http, proxy_host, proxy_port, []}])
  end
end
```

This calls `MyApp.Maestro.Transport.via_corp_proxy(request, ...args)` the
in-progress `Req.Request` is always the first argument, followed by
whatever's in `args` (which can itself use `{{placeholders}}`, resolved the
same way `payload`/`options` are, before `transport_mfa` runs). The function
must return a `Req.Request` back; anything else is a clean, assertion-
independent step failure, not a crash.

### Why `delete_option(:finch)`

The `http` client sends every request through one shared, named connection
pool (started once when Maestro boots) for efficient connection reuse.
`Req` doesn't allow combining that named pool with per-request
`connect_options` (where proxy/TLS settings live) it's one or the other.
Any `transport_mfa` hook that needs `connect_options` must drop `:finch`
first, trading pool reuse for a private connection on that one request
that's what `Req.Request.delete_option(:finch)` does above. A hook that
forgets this (or otherwise returns a `Req.Request` that's invalid in a way
only `Req` itself discovers) still fails cleanly it's caught and reported
as `{:invalid_transport_config, reason}`, never a crash.

### Trusting a self-signed certificate

Same shape, different `connect_options`:

```elixir
defmodule MyApp.Maestro.Transport do
  def insecure_tls(%Req.Request{} = req) do
    req
    |> Req.Request.delete_option(:finch)
    |> Req.merge(connect_options: [transport_opts: [verify: :verify_none]])
  end
end
```

## Errors

Every failure mode is a clean `{:error, reason}` it never crashes the test
run:

- `:missing_url` `options` didn't have a `url` at all.
- `{:invalid_url, url}` `url` isn't a string, or isn't an absolute
  `http`/`https` URL after templating.
- `{:invalid_method, value}` `method` isn't a non-empty string.
- `{:invalid_headers, value}` `headers` isn't a map.
- `{:invalid_query, value}` `query` isn't a map.
- `{:invalid_timeout, value}` `timeout` isn't a positive integer.
- `{:request_failed, reason}` connecting failed (refused, DNS failure,
  TLS error, ...) or the request timed out.
- `{:invalid_transport_mfa_directive, value}` `transport_mfa` isn't a
  `{"module": ..., "function": ...}` object.
- `{:mfa_module_not_found, module}` / `{:mfa_function_not_found, function}` /
  `{:mfa_not_exported, module, function, arity}` `transport_mfa` names
  something that doesn't exist or isn't callable with the given `args`.
- `{:mfa_raised, module, function, message}` the `transport_mfa` function
  itself raised.
- `{:invalid_transport_mfa_result, module, function, value}`
  `transport_mfa` didn't return a `Req.Request`.
- `{:invalid_transport_config, reason}` the `Req.Request` `transport_mfa`
  returned was invalid in a way only discovered once `Req` processed it
  (e.g. combining a named connection pool with `connect_options`, see
  [Why `delete_option(:finch)`](#why-delete_optionfinch) above).

Any status code (including 4xx/5xx) is still `{:ok, response}` an HTTP
error response is a normal, successful dispatch as far as the client is
concerned; it's `assert`'s job to decide whether `status: 500` is
acceptable for a given step.

A `send/2` failure like the ones above doesn't crash the run: it's caught
by `Maestro.Core.Runner.Step` and reported on the failed step as a
`Maestro.Client.Error` (`stage: :send, reason: :send_failed, details:
<the tuple above>`), the same structured shape any client's dispatch
failure ends up in, not just this one.
