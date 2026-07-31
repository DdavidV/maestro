# Maestro

Maestro is a declarative, cross-service integration test runner for Elixir.
Suites/scenarios/templates/datasets/test plans are plain JSON, runnable over REST, from a GUI,
or as an Elixir dependency, against any protocol a registered client speaks.

## A note on how this was built
- The core engine (`lib/maestro/`) was hand-written.
- The web GUI (`lib/maestro_web/`) and its test suite were built with heavy AI assistance (Claude).

## Getting started

Requires Elixir `~> 1.17`.

```bash
mix setup       # deps.get, install/build assets
mix test        # run the test suite
mix phx.server  # start the app at localhost:4000
```

To use Maestro as a dependency in a host application instead, add it to `mix.exs` and see
[docs/README.md](docs/README.md) for defining suites, registering clients/matchers/generators,
and running suites from your own code.

## Why Maestro

In a distributed environment where multiple nodes and microservices live, ExUnit, Common Test, and
the other test tooling provided by Erlang/Elixir or their equivalents in other languages and
frameworks might not be enough especially in the real world, where multiple teams work with
each other and API contracts can break between services that aren't even written in the same language.

Maestro addresses this by acting as an integrated test-running environment for integration testing
across service boundaries.

A test suite in Maestro can talk to any protocol a client is registered for (HTTP, Kafka, gRPC, raw TCP, ...),
so it can exercise a real, running system end-to-end rather than relying only on mocks for the other
side of a contract.
Suites are defined declaratively as JSON, so any tool or any person who doesn't know Elixir can
author, trigger, and inspect them:

- **Over REST** trigger a suite and poll for results from any language or tool (curl, Postman, a CI pipeline).
- **From a GUI** a suite is just data, so it can be built and browsed visually without touching code.
- **From Elixir code** since Maestro ships as a dependency, a host application can define suites,
scenarios, and step types directly and run them as part of its own test/dev workflow. Host applications
can also register their own clients and assertion matchers, so Maestro can be extended to speak a new
protocol or check a new kind of outcome without changing Maestro itself.

## What a suite looks like

A Maestro suite is a named collection of **testcases**, each an ordered list of **steps**.
A step either sends a rendered **template** through a registered **client** and optionally **asserts**
on the result, or it calls a reusable **scenario**, a shared step sequence like "log in and get a token"
defined once and referenced from any testcase, avoiding duplication of common flows across suites.

The data a step sends is a **dataset**: either inlined directly in the step, or a named reference to
a dataset defined elsewhere.
A dataset can hold a single set of values, or a table of rows if a step's dataset has rows,
the step (or scenario call) runs once per row automatically.

These building blocks are formalized as JSON Schema documents in [`priv/schemas/`](priv/schemas/):

Each schema file includes worked `examples` that double as fixtures for validating the format.

## The REST API

Beyond the GUI, Maestro exposes a plain JSON REST API (spec in
[`priv/openapi/maestro.yaml`](priv/openapi/maestro.yaml), served at `/api/docs`) so a CI pipeline,
`curl`, or any HTTP client can trigger and inspect runs without touching Elixir:

- **`POST /api/run`** trigger a run: body is `{"workspace_id": "...", "entries": [...]}`, where
  `entries` is the same list of suite paths `Maestro.run/2` itself takes. Returns a `run_id`.
- **`POST /api/workspaces/{workspace_id}/test-plan/{name}/run`** trigger a named test plan the
  same way, without listing its suites individually.
- **`GET /api/runs/{run_id}/status`** poll a run's status (`:pending`/`:running`/`:ok`/`:error`) as
  it progresses.
- **`GET /api/runs/{run_id}`** (optionally `?suite_id=&testcase_id=`) fetch the full result, or
  drill into one suite/testcase.
- **`GET /api/runs/{run_id}/report`** fetch the same HTML report the GUI renders, standalone.
- **`POST /api/runs/{run_id}/report`** write that report to disk on the server, returning its path.

The API is scoped to running suites/test plans and reading their status/results/reports only.
Creating, editing, or deleting workspaces and resources is a GUI-only capability, never exposed
over HTTP. Run history is the same in-memory store the GUI's history page reads from, so it's
lost on a server restart the same way.

## The web GUI

Beyond the REST API, Maestro ships a browser UI for authoring and running suites without
touching a text editor or curl:

- **Workspaces** a workspace is just a directory of suites/scenarios/datasets/templates/test plans;
  switch between them from the UI, each fully isolated (no cross-workspace references).
- **Browse and edit every resource kind** suites, scenarios, datasets, templates, and test plans all
  have list/search/paginate views and full create/edit forms, validated live against the same JSON
  Schemas the engine itself uses, with schema-sourced tooltips on every field.
  Deleting a resource is confirm-gated and immediate.
- **Run anything, from one place** a dedicated run picker lets you select any mix of suites and test
  plans and start them as a single run, or trigger a single suite/test plan straight from its own page.
- **Live run progress** a run's page updates in real time (suite/testcase/step status) as it
  executes, no polling or manual refresh.
- **Run history** every run started in a workspace is listed with its status and start time, until
  you clear it (in-memory history doesn't survive a server restart).
- **Reports** view a run's full report inline (matcher/expected/actual detail on every assertion),
  live-updating like the run page itself, or download it as a standalone HTML file at any point, even
  mid-run.
- **Breadcrumbs** on every page for quick, predictable navigation back up the hierarchy.

## Configuration

Everything below is `config :maestro, key: value` in a host application's own config
(`config.exs`/`runtime.exs`), read via `Application.get_env/2,3` never required to run Maestro
standalone, all of it has a working default out of the box.

- **`:host_app`** the OTP application name of the app embedding Maestro as a dependency
  (e.g. `:my_app`, matching that app's own `:app` in `mix.exs`). Used to locate a writable,
  release-safe `priv_dir` for Maestro's own runtime data.
  Raises at boot if set to something that isn't a loaded OTP application.
  Defaults to Maestro's own `priv_dir` if unset.
- **`:workspaces_registry_path`** absolute path to the JSON file the workspace registry (every
  workspace's name/id/root_dir) is persisted to. Defaults to `workspaces.json` under `:host_app`'s
  `priv_dir` (or Maestro's own, per above) if unset.
- **`:start_endpoint?`** (boolean) whether `MaestroWeb.Endpoint` (the web GUI) is started at all.
  Defaults to `true`; set to `false` for a host that only wants the Elixir API/runner, no HTTP
  server. `MaestroWeb.Endpoint`'s own config (`http:`/`secret_key_base`/`url:`/...) is filled in
  with working defaults at boot if a host hasn't set them (`config :maestro, MaestroWeb.Endpoint,
  ...`), so the GUI is reachable out of the box; an explicit host config always takes precedence.
- **`:report_dir`** root directory generated HTML reports are written under (each workspace gets
  its own subdirectory beneath it). Defaults to `reports` under `:host_app`'s `priv_dir` (or
  Maestro's own, if `:host_app` isn't set either.
- **`:report_layout`** a module implementing the `Maestro.Report.Layout` behaviour, for a host that
  wants to fully customize the generated HTML report's markup/styling. Defaults to the built-in
  `Maestro.Report.DefaultLayout`.
- **`:auto_report`** (boolean) whether a report is automatically generated to disk when a run
  finishes. Defaults to `true`; set to `false` if a host only ever wants reports on demand
  rather than one written for every run.
- **`:max_scenario_depth`** (integer) the maximum nesting depth of scenario-calling-scenario chains
  a suite is allowed, a backstop against pathological (but non-cyclic) nesting. Defaults to `50`.
- **`:http_pool_options`** options passed straight through to `Finch.start_link/1` for the built-in
  HTTP client's shared connection pool (pool size/count, per-host pools, ...). Defaults to `[]`
  (Finch's own defaults). See `Maestro.Clients.Http`'s docs for the full shape.
- **`:dns_cluster_query`** passed to `DNSCluster` for multi-node clustering in production (the
  standard Phoenix convention). Defaults to `:ignore`; irrelevant for a single-node setup.

## Using Maestro as a dependency

When Maestro is added as a dependency, its own runtime data (the workspace registry,
generated reports) needs somewhere to live. Always set `:host_app` in `config/config.exs`,
so it applies in every environment:

```elixir
# config/config.exs
config :maestro, host_app: :my_app
```

Leave `:workspaces_registry_path`/`:report_dir` unset there. Unset, they resolve to
`:code.priv_dir(:my_app)` (via `Maestro.Util.host_priv_dir/0`) (the *compiled* `priv/`
directory Mix copies into `_build` and that a release ships as-is) always writable,
always exists, in dev, in tests, and in a compiled release alike, with nothing further to
configure. This is the right (and only correct) behavior for a release, since a release has
no source tree on the target machine at all, only `_build`'s copy or whatever the release
packaged.

For local development only, it's convenient to instead have that data land in the `priv/`
directory sitting next to your own `mix.exs`, so you can browse/inspect it directly. Do this
in `config/dev.exs`, not `config.exs`: `dev.exs` is only ever loaded for `MIX_ENV=dev`, so a
compiled release (built with `MIX_ENV=prod`) never sees it and falls back to the release-safe
default above automatically, with nothing to remember to unset:

```elixir
# config/dev.exs
config :maestro,
  workspaces_registry_path: Path.expand("../priv/workspaces.json", __DIR__),
  report_dir: Path.expand("../priv/reports", __DIR__)
```

Both `workspaces_registry_path` and `report_dir` must be **absolute paths** `Path.expand/2`
(as above) is the safe way to make a path absolute at config time.

Neither value has to point under `priv/` at all any absolute path works. `priv/` is just a
convenient default: it's a directory Mix already knows how to package and ship as part of an
app, so pointing there means your suites/workspace data travel to a testing environment
alongside the rest of the release with no separate deploy step of their own. If your testing
environment already keeps its test files somewhere else (a mounted volume, a path a CI runner
checks out separately, a shared network path multiple app instances read from), point
`workspaces_registry_path`/`report_dir` at that location instead there's no requirement to
route everything through `priv/` if the environment you're actually deploying to already has
its own convention for where test files live.

### Workspace portability

A workspace's `root_dir` is always an absolute path in memory.
On disk, though, a `root_dir` that lives *under* the registry file's own directory
(the common case: a workspace created via the GUI's suggested path, or any `root_dir` under
`report_dir`'s directory) is stored **relative to the registry file**, not as a machine-specific
absolute path. A `root_dir` that genuinely lives elsewhere (a shared/mounted location outside that
directory tree) is stored absolute, unchanged.

This means the registry file and its workspace directories can be copied, deployed, or backed
up together as one portable unit and every workspace still resolves correctly on the new machine,
even though its absolute path is now different. Nothing needs to be re-entered or reconfigured
after such a move; only workspaces stored with a genuinely absolute (elsewhere) `root_dir` need that
location to still exist wherever the registry ends up running.

## Roadmap

**Simulators** (not yet implemented) are a planned feature for cases where the other side of a
contract genuinely can't be run for real in a test environment - an external system owned by a
third party, or one that simply doesn't live in the same codebase or team. A simulator would
stand in for that system, speaking its protocol well enough that a suite can still exercise and
verify its side of the contract without the real dependency being reachable.

This isn't implemented yet - the priority right now is polishing the core engine (suites,
scenarios, clients, matchers, generators, the runner itself) before adding new surface area.

## Further reading

See [docs/README.md](docs/README.md) for the full documentation index —
authoring suites/scenarios/templates/datasets/test plans, running them,
and writing your own clients/matchers/generators.

Licensed under the [MIT License](LICENSE).
