defmodule Maestro.Core.InterpolationTest do
  use ExUnit.Case, async: true

  alias Maestro.Core.Interpolation

  describe "render/2 with strings" do
    test "a whole-string placeholder preserves the context value's type" do
      assert Interpolation.render("{{qty}}", %{"qty" => 1}) == {:ok, 1}
      assert Interpolation.render("{{flag}}", %{"flag" => true}) == {:ok, true}
      assert Interpolation.render("{{nested}}", %{"nested" => %{"a" => 1}}) == {:ok, %{"a" => 1}}
    end

    test "a placeholder embedded in a larger string stringifies and concatenates" do
      assert Interpolation.render("Bearer {{token}}", %{"token" => "abc123"}) ==
               {:ok, "Bearer abc123"}

      assert Interpolation.render("qty={{qty}}", %{"qty" => 1}) == {:ok, "qty=1"}
    end

    test "multiple distinct placeholders in one string" do
      context = %{"a" => "1", "b" => "2"}
      assert Interpolation.render("{{a}}-{{b}}", context) == {:ok, "1-2"}
    end

    test "the same placeholder repeated in one string" do
      assert Interpolation.render("{{a}}{{a}}", %{"a" => "x"}) == {:ok, "xx"}
    end

    test "a string with no placeholders passes through unchanged" do
      assert Interpolation.render("plain string", %{}) == {:ok, "plain string"}
    end

    test "a missing key in a whole-string placeholder is an error" do
      assert Interpolation.render("{{missing}}", %{}) ==
               {:error, {:missing_interpolation_key, "missing"}}
    end

    test "a missing key in a mixed string is an error" do
      assert Interpolation.render("Bearer {{missing}}", %{}) ==
               {:error, {:missing_interpolation_key, "missing"}}
    end
  end

  describe "render/2 with maps" do
    test "recurses into every value, keys untouched" do
      context = %{"order_id" => "123", "total" => 42}

      assert Interpolation.render(
               %{"event" => "order_created", "order_id" => "{{order_id}}", "total" => "{{total}}"},
               context
             ) == {:ok, %{"event" => "order_created", "order_id" => "123", "total" => 42}}
    end

    test "propagates a missing-key error from a nested value" do
      assert Interpolation.render(%{"a" => "{{missing}}"}, %{}) ==
               {:error, {:missing_interpolation_key, "missing"}}
    end

    test "an empty map renders to an empty map" do
      assert Interpolation.render(%{}, %{"a" => 1}) == {:ok, %{}}
    end
  end

  describe "render/2 with lists" do
    test "recurses into every element, preserving order" do
      assert Interpolation.render(["{{a}}", "{{b}}", "literal"], %{"a" => 1, "b" => 2}) ==
               {:ok, [1, 2, "literal"]}
    end

    test "propagates a missing-key error from an element" do
      assert Interpolation.render(["{{missing}}"], %{}) ==
               {:error, {:missing_interpolation_key, "missing"}}
    end
  end

  describe "render/2 with nested structures" do
    test "maps and lists compose" do
      context = %{"id" => "abc", "amounts" => [1, 2]}

      assert Interpolation.render(
               %{"id" => "{{id}}", "tags" => ["fixed", "{{id}}"]},
               context
             ) == {:ok, %{"id" => "abc", "tags" => ["fixed", "abc"]}}
    end

    test "arbitrarily deep map/list nesting resolves at every level, types preserved" do
      deep = %{
        "user" => %{
          "name" => "{{name}}",
          "roles" => [
            "{{role1}}",
            %{"label" => "{{role2}}", "nested" => %{"deep" => "{{deep_val}}"}}
          ]
        },
        "items" => [
          %{"id" => 1, "tags" => [%{"k" => "{{tag}}"}]},
          "{{plain}}"
        ]
      }

      context = %{
        "name" => "alice",
        "role1" => "admin",
        "role2" => "editor",
        "deep_val" => 42,
        "tag" => "urgent",
        "plain" => "leaf"
      }

      assert Interpolation.render(deep, context) ==
               {:ok,
                %{
                  "user" => %{
                    "name" => "alice",
                    "roles" => ["admin", %{"label" => "editor", "nested" => %{"deep" => 42}}]
                  },
                  "items" => [%{"id" => 1, "tags" => [%{"k" => "urgent"}]}, "leaf"]
                }}
    end

    test "a missing key buried several levels deep in map/list nesting still errors" do
      broken = %{"a" => [%{"b" => [%{"c" => "{{missing}}"}]}]}
      assert Interpolation.render(broken, %{}) == {:error, {:missing_interpolation_key, "missing"}}
    end
  end

  describe "render/2 with non-string, non-collection values" do
    test "numbers, booleans, and nil pass through unchanged" do
      assert Interpolation.render(42, %{}) == {:ok, 42}
      assert Interpolation.render(true, %{}) == {:ok, true}
      assert Interpolation.render(nil, %{}) == {:ok, nil}
    end
  end
end
