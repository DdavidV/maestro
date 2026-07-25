defmodule Maestro.Matchers.JsonSchemaMatch do
  @moduledoc """
  Built-in matcher, registered as `"json_schema_match"`, that validates a
  step's response (or a `path`-selected part of it) against a JSON Schema.

  Unlike `Maestro.Matchers.JsonMatch`, `expected` here isn't a value/shape to
  structurally compare against it *is* a JSON Schema document (draft-07),
  and `actual` passes the check if it validates against that schema. This is
  the right tool when you care about a contract (types, required fields,
  enums, formats, nested `$ref`s, ...) rather than pinning exact values.

  `expected` is rendered through `Maestro.Core.Interpolation.render/2`
  against the step's dataset/saved state first, exactly like `json_match`,
  so a schema can reference dataset fields (e.g. an `"enum"` list built from
  `{{allowed_statuses}}`) before it's used to validate. `path` (optional)
  selects a sub-value of the step's response to validate, via
  `Maestro.Core.JsonPath`; if omitted, the whole response is validated.

  ## Example

      {
        "matcher": "json_schema_match",
        "path": "$.order",
        "expected": {
          "type": "object",
          "required": ["id", "status"],
          "properties": {
            "id": { "type": "integer" },
            "status": { "type": "string", "enum": ["pending", "confirmed"] }
          }
        }
      }

  A schema that doesn't itself pass JSON Schema meta-schema validation (a
  typo like `"type": "sting"`, or `expected` not being an object/map at all)
  is a normal assertion failure (`{:invalid_schema, reason}`), not a crash.
  """

  use Maestro.Assert.Matcher, name: "json_schema_match"

  alias Maestro.Core.Interpolation
  alias Maestro.Core.JsonPath

  @impl true
  def match(assertion, actual, context) do
    with {:ok, target} <- select_target(assertion, actual),
         {:ok, expected} <- Interpolation.render(assertion.expected, context),
         {:ok, schema} <- resolve_schema(expected) do
      case ExJsonSchema.Validator.validate(schema, target) do
        :ok -> :ok
        {:error, reasons} -> {:error, {:schema_validation_failed, reasons}}
      end
    end
  end

  defp select_target(%{path: path}, actual) do
    case JsonPath.extract(actual, path) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:path_not_found, path, reason}}
    end
  end

  defp select_target(_assertion, actual), do: {:ok, actual}

  defp resolve_schema(expected) do
    {:ok, ExJsonSchema.Schema.resolve(expected)}
  rescue
    e -> {:error, {:invalid_schema, Exception.message(e)}}
  end
end
