defmodule Maestro.Core.JsonPathTest do
  use ExUnit.Case, async: true

  alias Maestro.Core.JsonPath

  describe "extract/2" do
    test "extracts a top-level field" do
      assert JsonPath.extract(%{"token" => "abc"}, "$.token") == {:ok, "abc"}
    end

    test "extracts a nested field" do
      value = %{"data" => %{"items" => [1, 2, 3]}}
      assert JsonPath.extract(value, "$.data.items") == {:ok, [1, 2, 3]}
    end

    test "the root itself, with an empty rest" do
      assert JsonPath.extract(%{"a" => 1}, "$.a") == {:ok, 1}
    end

    test "a missing key surfaces {:missing_key, key}" do
      assert JsonPath.extract(%{"a" => 1}, "$.missing") == {:error, {:missing_key, "missing"}}
    end

    test "stepping into a non-indexable (scalar) value surfaces {:not_indexable, value}" do
      assert JsonPath.extract(%{"a" => 1}, "$.a.b") == {:error, {:not_indexable, 1}}
    end

    test "a path not starting with \"$.\" surfaces {:invalid_path, path}" do
      assert JsonPath.extract(%{"a" => 1}, "a") == {:error, {:invalid_path, "a"}}
      assert JsonPath.extract(%{"a" => 1}, "") == {:error, {:invalid_path, ""}}
    end

    test "a non-map, non-list root value with a path surfaces {:not_indexable, value}" do
      assert JsonPath.extract("just a string", "$.a") ==
               {:error, {:not_indexable, "just a string"}}

      assert JsonPath.extract(42, "$.a") == {:error, {:not_indexable, 42}}
    end
  end

  describe "extract/2 with list indexing" do
    test "indexes into a top-level list, 0-based" do
      assert JsonPath.extract(["a", "b", "c"], "$.0") == {:ok, "a"}
      assert JsonPath.extract(["a", "b", "c"], "$.1") == {:ok, "b"}
      assert JsonPath.extract(["a", "b", "c"], "$.2") == {:ok, "c"}
    end

    test "indexes into a nested list" do
      value = %{"items" => [10, 20, 30]}
      assert JsonPath.extract(value, "$.items.1") == {:ok, 20}
    end

    test "steps through a list element into a map" do
      value = %{"items" => [%{"id" => 1}, %{"id" => 2}]}
      assert JsonPath.extract(value, "$.items.1.id") == {:ok, 2}
    end

    test "steps through nested lists" do
      value = [[1, 2], [3, 4]]
      assert JsonPath.extract(value, "$.1.0") == {:ok, 3}
    end

    test "an out-of-range index surfaces {:index_out_of_range, index, length}" do
      assert JsonPath.extract([1, 2], "$.5") == {:error, {:index_out_of_range, 5, 2}}
    end

    test "a negative index is an error, not \"from the end\"" do
      assert JsonPath.extract([1, 2, 3], "$.-1") == {:error, {:invalid_index, "-1"}}
    end

    test "a non-numeric segment against a list surfaces {:invalid_index, segment}" do
      assert JsonPath.extract([1, 2, 3], "$.foo") == {:error, {:invalid_index, "foo"}}
    end

    test "a segment that is only partially numeric is an error, not a truncated parse" do
      assert JsonPath.extract([1, 2, 3], "$.1abc") == {:error, {:invalid_index, "1abc"}}
    end

    test "a numeric segment against a map is looked up as a literal key, not an index" do
      assert JsonPath.extract(%{"0" => "zero"}, "$.0") == {:ok, "zero"}
    end

    test "the same path resolves against either shape: a list by index or a map by literal key" do
      assert JsonPath.extract(%{"data" => ["x", "a"]}, "$.data.1") == {:ok, "a"}
      assert JsonPath.extract(%{"data" => %{"1" => "a"}}, "$.data.1") == {:ok, "a"}
    end
  end
end
