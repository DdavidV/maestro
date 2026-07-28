# Maestro documentation

## Authoring

Building blocks of a Maestro suite, in the order you'll likely reach for
them:

- [dataset.md](dataset.md) reusable test data (`data`/`rows`), and
  `$generated` values that can't be static.
- [template.md](template.md) reusable message/payload shapes with
  `{{placeholder}}`s.
- [scenario.md](scenario.md) reusable step sequences, callable from any
  testcase.
- [suite.md](suite.md) testcases, steps, assertions, and saving values
  between steps. Start here if you're new to Maestro.
- [test_plan.md](test_plan.md) grouping several suites to run together.

## Running

- [maestro.md](maestro.md) `Maestro.run/1`/`run_test_plan/1`, checking
  progress and results.
- REST API: a thin HTTP wrapper over the same functions. See
  `priv/openapi/maestro.yaml` (served as Swagger UI at `/api/docs`) and
  `lib/maestro_web/api/run_handler.ex`.
- [report.md](report.md) generating the HTML report, what it contains,
  and writing a custom report layout.

## Built-ins

- [http_client.md](http_client.md) the built-in `http` client.
- [json_match.md](json_match.md) the default assertion matcher, for
  structural/value matching.
- [json_schema_match.md](json_schema_match.md) an assertion matcher for
  validating a response against a JSON Schema contract.

## Extending Maestro

- [behaviours.md](behaviours.md) writing your own client, assertion
  matcher, or dataset value generator.

## Schemas

Every authoring format above is formalized as a JSON Schema document
under [`priv/schemas/`](../priv/schemas/), each with worked `examples`
that double as fixtures for validating the format.
