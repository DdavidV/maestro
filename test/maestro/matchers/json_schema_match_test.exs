defmodule Maestro.Matchers.JsonSchemaMatchTest do
  use ExUnit.Case, async: true

  alias Maestro.Matchers.JsonSchemaMatch

  defp match(expected, actual, context \\ %{}) do
    JsonSchemaMatch.match(%{expected: expected}, actual, context)
  end

  describe "name/0" do
    test "is registered as json_schema_match" do
      assert JsonSchemaMatch.name() == "json_schema_match"
    end
  end

  describe "basic type validation" do
    test "a matching scalar type passes" do
      assert match(%{"type" => "string"}, "hello") == :ok
      assert match(%{"type" => "integer"}, 42) == :ok
      assert match(%{"type" => "boolean"}, true) == :ok
      assert match(%{"type" => "null"}, nil) == :ok
    end

    test "a mismatching scalar type fails with a schema_validation_failed reason" do
      assert {:error, {:schema_validation_failed, reasons}} =
               match(%{"type" => "string"}, 42)

      assert [{_message, "#"}] = reasons
    end
  end

  describe "object schemas" do
    @schema %{
      "type" => "object",
      "required" => ["id", "status"],
      "properties" => %{
        "id" => %{"type" => "integer"},
        "status" => %{"type" => "string", "enum" => ["pending", "confirmed"]}
      }
    }

    test "a valid object passes" do
      assert match(@schema, %{"id" => 1, "status" => "confirmed"}) == :ok
    end

    test "extra fields not mentioned in properties are allowed by default" do
      actual = %{"id" => 1, "status" => "confirmed", "extra" => "field"}
      assert match(@schema, actual) == :ok
    end

    test "a missing required field fails" do
      assert {:error, {:schema_validation_failed, reasons}} =
               match(@schema, %{"status" => "confirmed"})

      assert [{message, "#"}] = reasons
      assert message =~ "id"
    end

    test "a value outside the enum fails" do
      assert {:error, {:schema_validation_failed, reasons}} =
               match(@schema, %{"id" => 1, "status" => "cancelled"})

      assert [{_message, "#/status"}] = reasons
    end

    test "additionalProperties: false rejects extra fields" do
      schema = Map.put(@schema, "additionalProperties", false)
      actual = %{"id" => 1, "status" => "confirmed", "extra" => "field"}

      assert {:error, {:schema_validation_failed, _reasons}} = match(schema, actual)
    end
  end

  describe "array schemas" do
    @schema %{
      "type" => "array",
      "items" => %{"type" => "integer"},
      "minItems" => 1
    }

    test "a matching array passes" do
      assert match(@schema, [1, 2, 3]) == :ok
    end

    test "an element of the wrong type fails" do
      assert {:error, {:schema_validation_failed, reasons}} = match(@schema, [1, "two"])
      assert [{_message, "#/1"}] = reasons
    end

    test "an empty array fails minItems" do
      assert {:error, {:schema_validation_failed, _reasons}} = match(@schema, [])
    end
  end

  describe "malformed schemas" do
    test "a schema that fails meta-schema validation is a normal error, not a crash" do
      assert {:error, {:invalid_schema, _message}} =
               match(%{"type" => "not_a_real_type"}, "anything")
    end

    test "a non-map expected is a normal error, not a crash" do
      assert {:error, {:invalid_schema, _message}} = match("not a schema", "anything")
    end
  end

  describe "path selection" do
    test "validates only the value at path, when given" do
      actual = %{"order" => %{"id" => 1, "status" => "confirmed"}}
      schema = %{"type" => "object", "required" => ["id"]}

      assert JsonSchemaMatch.match(%{expected: schema, path: "$.order"}, actual, %{}) == :ok
    end

    test "an unresolvable path surfaces path_not_found" do
      actual = %{"order" => %{}}
      schema = %{"type" => "object"}

      assert JsonSchemaMatch.match(%{expected: schema, path: "$.missing"}, actual, %{}) ==
               {:error, {:path_not_found, "$.missing", {:missing_key, "missing"}}}
    end
  end

  describe "templating" do
    test "expected (the schema) is interpolated against context before validating" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "status" => %{"type" => "string", "enum" => ["{{allowed_status}}"]}
        }
      }

      context = %{"allowed_status" => "confirmed"}

      assert match(schema, %{"status" => "confirmed"}, context) == :ok
      assert {:error, _reason} = match(schema, %{"status" => "pending"}, context)
    end

    test "a placeholder referencing a missing context key is a hard error" do
      schema = %{"type" => "{{missing}}"}
      assert {:error, _reason} = match(schema, "anything", %{})
    end
  end
end
