# Maestro

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
can also register their own clients and assertion providers, so Maestro can be extended to speak a new
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
