defmodule Maestro.Clients.Http do
  @moduledoc """
  Maestro's built-in HTTP client, registered as `"http"`.

  ## Connection pool configuration

  Every request goes through one shared `Finch` connection pool, started
  once in `init_client/0`. Its options come from
  `config :maestro, :http_pool_options, [...]`, passed to
  `Finch.start_link/1` as-is (`:name` is always set by this client and
  can't be overridden). Defaults to `[]` (Finch's own defaults: a single
  pool of 50 connections). A host application running against a real test
  environment might raise pool size/count, or configure per-host pools:

  ```elixir
  config :maestro, :http_pool_options,
    pools: %{
      default: [size: 50, count: 4],
      "https://slow-legacy-service.example.com" => [size: 4, count: 1]
    }
  ```

  See `Finch.start_link/1`'s own docs for every available option (pool
  size/count, protocol, connection options, ...) Maestro doesn't re-model
  them, the same "pass it straight through" approach `transport_mfa` (below)
  takes for per-request transport config.

  `init_client/0`'s `t:client_state/0` is `%{finch_name: Finch.name(),
  finch_pid: pid}`, not a bare pid a named field is self-documenting at
  every call site, and leaves room to grow without changing shape.

  Sends `payload` as the request body and reads request configuration from
  `options` (see `priv/schemas/template.schema.json`'s `"http"` example):

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
    "payload": { "foo": "{{foo}}" }
  }
  ```

  - **`method`** optional, defaults to `"GET"`. Case-insensitive
    (`"post"`/`"POST"` both work).
  - **`url`** required. Must be an absolute `http`/`https` URL after
    templating a relative or non-http(s) URL is a hard error rather than a
    silent no-op.
  - **`headers`** optional, defaults to `%{}`. A flat string-to-string map.
  - **`query`** optional. A flat map of query-string parameters, merged into
    any query string already present on `url`.
  - **`timeout`** optional, milliseconds, defaults to 5000. Caps the whole
    request (connecting, sending, and receiving the response).
  - **`payload`** the request body. A map is sent as JSON (with
    `content-type: application/json` set automatically unless `headers`
    already specifies one); a string is sent as-is; an empty map (the
    default when a template omits `payload`) sends no body.
  - **`transport_mfa`** optional escape hatch for anything above doesn't
    cover proxies, client TLS certs, custom CA bundles, `verify: :none`
    for a self-signed staging cert, unix sockets, forcing HTTP/1 vs
    HTTP/2, or any other `Req`/`Finch`/`Mint`-level concern a real (not
    local/sandboxed) test environment needs. See below.

  ## `transport_mfa`: configuring the underlying transport

  `method`/`url`/`headers`/`query`/`timeout` cover the common case, but
  Maestro doesn't attempt to model every `Req`/`Finch`/`Mint` option (proxy
  settings, TLS verification, connection pooling, ...) that list is long
  and keeps growing. Instead, `transport_mfa` names an already-loaded
  function that receives the in-progress `Req.Request` and returns a
  (possibly modified) one:

  ```json
  {
    "options": {
      "url": "https://internal-staging.example.com/orders",
      "transport_mfa": {
        "module": "MyApp.Maestro.Transport",
        "function": "via_corp_proxy",
        "args": ["{{proxy_host}}", 8080]
      }
    }
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
  whatever's in `args` (which can itself use `{{placeholders}}`, resolved
  the same way `payload`/`options` are before `transport_mfa` runs). The
  function must return a `Req.Request` anything else is a clean assertion-
  independent step failure, not a crash.

  Note the `Req.Request.delete_option(:finch)` above: this client sends
  every request through one shared, named connection pool (started once in
  `init_client/0`) for efficient connection reuse, and `Req` doesn't allow
  combining a named pool with per-request `connect_options` (where
  proxy/TLS settings live) it's one or the other. Any `transport_mfa` hook
  that needs `connect_options` must drop `:finch` first, trading pool reuse
  for that one request. Forgetting to (or any other invalid `Req.Request`
  a hook builds) is still just a clean `{:invalid_transport_config,
  reason}` step failure, never a crash `Req` itself raises rather than
  returning an error tuple for a handful of misconfigurations like this
  one, so that raise is rescued here the same way a normal network failure
  already is.

  ## Response shape

  `send/2` returns `{:ok, response}` where `response` is:

  ```elixir
  %{"status" => 200, "headers" => %{"content-type" => ["application/json"]}, "body" => ...}
  ```

  `"body"` is JSON-decoded into a map/list automatically when the response's
  `content-type` says `application/json` (so `path`-based assertions like
  `json_match`/`json_schema_match` can dig straight into it); otherwise it's
  the raw response body as a string. `"headers"` groups repeated header
  names into a list of values (HTTP allows a header to appear more than
  once), always present even for headers that appeared only once.

  A connection failure, timeout, or malformed `options` (missing/invalid
  `url`, unsupported `method`) is `{:error, reason}` it never raises, and
  is surfaced as a normal step-dispatch failure like any other client error.
  """

  use Maestro.Client, name: "http"

  alias Maestro.Core.SafeMFA

  @default_timeout 5_000

  @type client_state :: %{finch_name: Finch.name(), finch_pid: pid}

  @impl true
  def init_client do
    pool_options = Application.get_env(:maestro, :http_pool_options, [])
    finch_name = __MODULE__.Finch

    case Finch.start_link(Keyword.put(pool_options, :name, finch_name)) do
      {:ok, pid} -> {:ok, %{finch_name: finch_name, finch_pid: pid}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def send(%{finch_name: finch_name}, %{"payload" => payload, "options" => options}) do
    with {:ok, method} <- fetch_method(options),
         {:ok, url} <- fetch_url(options),
         {:ok, headers} <- fetch_headers(options),
         {:ok, query} <- fetch_query(options),
         {:ok, timeout} <- fetch_timeout(options),
         {:ok, body, headers} <- encode_body(payload, headers) do
      request(
        finch_name,
        method,
        url,
        query,
        headers,
        body,
        timeout,
        Map.get(options, "transport_mfa")
      )
    end
  end

  defp fetch_method(options) do
    case Map.get(options, "method", "GET") do
      method when is_binary(method) and method != "" -> {:ok, String.upcase(method)}
      other -> {:error, {:invalid_method, other}}
    end
  end

  defp fetch_url(options) do
    case Map.fetch(options, "url") do
      {:ok, url} when is_binary(url) ->
        case URI.new(url) do
          {:ok, %URI{scheme: scheme}} when scheme in ["http", "https"] -> {:ok, url}
          _ -> {:error, {:invalid_url, url}}
        end

      {:ok, other} ->
        {:error, {:invalid_url, other}}

      :error ->
        {:error, :missing_url}
    end
  end

  defp fetch_headers(options) do
    case Map.get(options, "headers", %{}) do
      headers when is_map(headers) -> {:ok, Map.new(headers, fn {k, v} -> {to_string(k), v} end)}
      other -> {:error, {:invalid_headers, other}}
    end
  end

  defp fetch_query(options) do
    case Map.get(options, "query", %{}) do
      query when is_map(query) -> {:ok, query}
      other -> {:error, {:invalid_query, other}}
    end
  end

  defp fetch_timeout(options) do
    case Map.get(options, "timeout", @default_timeout) do
      timeout when is_integer(timeout) and timeout > 0 -> {:ok, timeout}
      other -> {:error, {:invalid_timeout, other}}
    end
  end

  defp encode_body(payload, headers) when is_map(payload) and map_size(payload) == 0 do
    {:ok, nil, headers}
  end

  defp encode_body(payload, headers) when is_map(payload) do
    if Enum.any?(headers, fn {k, _v} -> String.downcase(k) == "content-type" end) do
      {:ok, Jason.encode!(payload), headers}
    else
      {:ok, Jason.encode!(payload), Map.put(headers, "content-type", "application/json")}
    end
  end

  defp encode_body(payload, headers) when is_binary(payload), do: {:ok, payload, headers}

  defp request(finch_name, method, url, query, headers, body, timeout, transport_mfa) do
    req =
      Req.new(
        method: method,
        url: url,
        params: query,
        headers: headers,
        body: body,
        receive_timeout: timeout,
        finch: finch_name,
        retry: false
      )

    with {:ok, req} <- apply_transport_mfa(req, transport_mfa) do
      run_request(req)
    end
  end

  # transport_mfa can build a Req.Request that's only discovered to be
  # invalid once Req actually processes it (e.g. combining :finch, our
  # named connection pool, with :connect_options, which Req rejects by
  # raising rather than returning {:error, _}) so this, unlike a plain
  # network failure (which Req already reports as {:error, exception}),
  # needs its own rescue to uphold the same "a malformed step never
  # crashes the run" guarantee transport_mfa's docs promise.
  defp run_request(req) do
    case Req.request(req) do
      {:ok, %Req.Response{} = response} -> {:ok, format_response(response)}
      {:error, exception} -> {:error, {:request_failed, Exception.message(exception)}}
    end
  rescue
    e -> {:error, {:invalid_transport_config, Exception.message(e)}}
  end

  defp apply_transport_mfa(req, nil), do: {:ok, req}

  defp apply_transport_mfa(req, %{"module" => mod_str, "function" => fun_str} = mfa)
       when is_binary(mod_str) and is_binary(fun_str) do
    args = Map.get(mfa, "args", [])

    case SafeMFA.apply(mod_str, fun_str, [req | args]) do
      {:ok, _module, _function, %Req.Request{} = req} ->
        {:ok, req}

      {:ok, module, function, other} ->
        {:error, {:invalid_transport_mfa_result, module, function, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_transport_mfa(_req, mfa), do: {:error, {:invalid_transport_mfa_directive, mfa}}

  defp format_response(%Req.Response{status: status, headers: headers, body: body}) do
    %{"status" => status, "headers" => headers, "body" => decode_body(body, headers)}
  end

  defp decode_body(body, headers) when is_binary(body) do
    if json_content_type?(headers) do
      case Jason.decode(body) do
        {:ok, decoded} -> decoded
        {:error, _reason} -> body
      end
    else
      body
    end
  end

  defp decode_body(body, _headers), do: body

  defp json_content_type?(headers) do
    headers
    |> Map.get("content-type", [])
    |> Enum.any?(&String.contains?(&1, "application/json"))
  end
end
