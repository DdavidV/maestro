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
For the cases where the other side of a contract genuinely can't be run for real could be an external
system owned by a third party, or one that simply doesn't live in the same codebase or team:
simulators are part of Maestro's architecture, standing in for that system so its side of the contract
can still be exercised and verified.
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

## Further reading

See [docs/README.md](docs/README.md) for the full documentation index —
authoring suites/scenarios/templates/datasets/test plans, running them,
and writing your own clients/matchers/generators.

Licensed under the [MIT License](LICENSE).
