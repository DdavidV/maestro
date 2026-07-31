# MiniBank

A small in-memory banking system, and a fully worked example of using
[Maestro](../..) as a dependency: a custom `Maestro.Client` on a non-HTTP
protocol, a second custom client that imitates querying a database, a
custom `Maestro.Assert.Matcher`, custom `Maestro.Generator`s, Maestro's
built-in `http` client and `json_schema_match` matcher used against a real
HTTP server, and a checked-in Maestro workspace with 6 suites, a reusable
scenario, a reusable template, and a test plan tying it all together.

## Running it

```bash
cd examples/mini_bank
mix deps.get
iex -S mix phx.server
```

```elixir
{:ok, workspace} = Maestro.Workspaces.get("minibank")
{:ok, run_id} = Maestro.run_test_plan(workspace, "full_regression")

# poll until done
Maestro.status(run_id)
# => {:ok, %{run_id: ..., status: :ok, suites: [...]}}   (once finished)

{:ok, result} = Maestro.result(run_id)
```

Or run a single suite directly:

```elixir
{:ok, run_id} = Maestro.run(workspace, ["transfer_insufficient_funds"])
Maestro.status(run_id)
```

Or, instead of driving runs from `iex`, do the same thing visually: open
**http://localhost:4000**, pick the "MiniBank" workspace, and trigger/watch
runs from Maestro's own built-in web GUI (see below).

### What you should see

Once the full regression test plan finishes, `Maestro.status/1` should
report `status: :ok` with all 6 suites `:ok`.

## Extension points at a glance

| Maestro behaviour        | File                                         | Built-in or custom? |
|--------------------------|----------------------------------------------|----------------------|
| `Maestro.Client`         | `lib/mini_bank/maestro/wire_client.ex`       | Custom (`"wire"`) a hand-rolled NDJSON-over-TCP protocol |
| `Maestro.Client`         | `lib/mini_bank/maestro/db_client.ex`         | Custom (`"db_client"`) imitates a DB read, actually a direct ETS lookup |
| `Maestro.Assert.Matcher` | `lib/mini_bank/maestro/money_matcher.ex`     | Custom (`"money_equals"`) integer-safe monetary comparisons |
| `Maestro.Generator`      | `lib/mini_bank/maestro/generators.ex`        | Custom `account_number`, `http_base_url` |

`priv/workspace/templates/open_account_wire.json` is a reusable template (referenced by path,
rather than inlined, from `open_session` and two of the transfer suites) showing how a
template file avoids repeating the same `client`/`payload` shape across every step that opens
an account.

The `bulk_account_opening` suite shows a `rows`-type dataset (`priv/workspace/datasets/new_customers.json`):
a single step, driven by a table of new customers, runs once per row - each row opening its
own account and independently asserting its own expected owner/balance.

## The banking domain

`MiniBank.Bank` is a `GenServer` that owns an ETS table of accounts
(`account_number => balance/owner`). Every mutation (`open_account/3`,
`deposit/2`, `withdraw/2`, `transfer/3`) goes through the `GenServer`, so
concurrent writes serialize and a transfer's debit+credit is always
atomic. A read can either go through the `GenServer` too, or bypass it
entirely via a direct `:ets.lookup/2` which is exactly what
`MiniBank.Maestro.DbClient` does, standing in for a read-replica database.

`mix test` runs `test/mini_bank/bank_test.exs`, a plain ExUnit suite that
exercises this domain logic directly (no Maestro, no TCP, no HTTP
involved) a useful independent check that the domain itself is correct,
separate from whether Maestro's suites exercise it correctly over the
wire/HTTP.
