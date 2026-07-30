defmodule Maestro.Resources.SchemaDocsTest do
  use ExUnit.Case, async: true

  alias Maestro.Resources.SchemaDocs

  describe "tooltip/2" do
    test "returns the exact description for a top-level field" do
      assert SchemaDocs.tooltip(:suite, ["tags"]) =~ "filtering/grouping suites"
      assert SchemaDocs.tooltip(:test_plan, ["test_suites"]) =~ "Ordered list of suite file paths"
      assert SchemaDocs.tooltip(:scenario, ["steps"]) =~ "Ordered list of steps"
    end

    test "resolves a $ref'd field (dataset/template properties defined via $defs)" do
      assert SchemaDocs.tooltip(:dataset, ["data"]) =~ "A single bag of values"
      assert SchemaDocs.tooltip(:dataset, ["rows"]) =~ "Rows of values for data-driven iteration"
      assert SchemaDocs.tooltip(:template, ["clients"]) =~ "Names of the registered clients"
      assert SchemaDocs.tooltip(:template, ["payload"]) =~ "message/payload content itself"
      assert SchemaDocs.tooltip(:template, ["options"]) =~ "Client configuration for sending"
    end

    test "returns nil for an unknown field path" do
      assert SchemaDocs.tooltip(:suite, ["nonexistent"]) == nil
    end
  end
end
