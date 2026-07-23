defmodule Maestro.Matchers.JsonMatchTest do
  use ExUnit.Case, async: true

  alias Maestro.Matchers.JsonMatch

  defmodule Checks do
    def within_days(actual, expected_date, days) when is_binary(actual) do
      {:ok, actual_date} = Date.from_iso8601(actual)
      {:ok, target_date} = Date.from_iso8601(expected_date)
      abs(Date.diff(actual_date, target_date)) <= days
    end

    def always_true(_actual), do: true
    def always_false(_actual), do: false
    def always_ok(_actual), do: :ok
    def always_error(_actual), do: {:error, :nope}
    def boom(_actual), do: raise("kaboom")
    def weird_result(_actual), do: :not_a_valid_result
  end

  defp match(expected, actual, context \\ %{}) do
    JsonMatch.match(%{expected: expected}, actual, context)
  end

  describe "scalar equality" do
    test "matching values of every scalar type pass" do
      assert match("abc", "abc") == :ok
      assert match(42, 42) == :ok
      assert match(true, true) == :ok
      assert match(nil, nil) == :ok
    end

    test "mismatching scalars fail with the values" do
      assert match("abc", "xyz") == {:error, {:not_equal, "abc", "xyz"}}
      assert match(42, 43) == {:error, {:not_equal, 42, 43}}
      assert match(true, false) == {:error, {:not_equal, true, false}}
    end
  end

  describe "nested object matching" do
    test "every field matching passes" do
      expected = %{"id" => 1, "name" => "alice"}
      actual = %{"id" => 1, "name" => "alice"}
      assert match(expected, actual) == :ok
    end

    test "extra fields in actual are allowed by default (open matching)" do
      expected = %{"id" => 1}
      actual = %{"id" => 1, "extra" => "field"}
      assert match(expected, actual) == :ok
    end

    test "one mismatching field fails, tagged with its key" do
      expected = %{"id" => 1, "name" => "alice"}
      actual = %{"id" => 1, "name" => "bob"}

      assert match(expected, actual) ==
               {:error, {:field_mismatch, "name", {:not_equal, "alice", "bob"}}}
    end

    test "a missing expected key fails" do
      expected = %{"id" => 1, "name" => "alice"}
      actual = %{"id" => 1}
      assert match(expected, actual) == {:error, {:expected_key_missing, "name"}}
    end
  end

  describe "$expected / $unexpected" do
    test "$expected: key present with any value passes" do
      assert match(%{"token" => "$expected"}, %{"token" => "abc123"}) == :ok
      assert match(%{"token" => "$expected"}, %{"token" => nil}) == :ok
    end

    test "$expected: key absent fails" do
      assert match(%{"token" => "$expected"}, %{}) == {:error, {:expected_key_missing, "token"}}
    end

    test "$unexpected: key absent passes" do
      assert match(%{"internal" => "$unexpected"}, %{"id" => 1}) == :ok
    end

    test "$unexpected: key present fails, even when its value is null" do
      assert match(%{"internal" => "$unexpected"}, %{"internal" => "leaked"}) ==
               {:error, {:unexpected_key_present, "internal"}}

      assert match(%{"internal" => "$unexpected"}, %{"internal" => nil}) ==
               {:error, {:unexpected_key_present, "internal"}}
    end
  end

  describe "$_ closed-object directive" do
    test "no extra keys beyond those named passes" do
      expected = %{"id" => 1, "$_" => "$unexpected"}
      assert match(expected, %{"id" => 1}) == :ok
    end

    test "one extra key fails" do
      expected = %{"id" => 1, "$_" => "$unexpected"}

      assert match(expected, %{"id" => 1, "extra" => "field"}) ==
               {:error, {:unexpected_extra_keys, ["extra"]}}
    end

    test "closing applies at nested depth too, not just the top level" do
      expected = %{"user" => %{"id" => 1, "$_" => "$unexpected"}}
      actual = %{"user" => %{"id" => 1, "secret" => "leaked"}}

      assert match(expected, actual) ==
               {:error, {:field_mismatch, "user", {:unexpected_extra_keys, ["secret"]}}}
    end

    test "an invalid $_ pairing is a hard error, not silently ignored" do
      expected = %{"id" => 1, "$_" => true}
      assert match(expected, %{"id" => 1}) == {:error, {:invalid_closed_object_directive, true}}
    end
  end

  describe "ordered list matching (bare arrays)" do
    test "exact match in order passes" do
      assert match([1, 2, 3], [1, 2, 3]) == :ok
    end

    test "wrong order fails at the first mismatching index" do
      assert match([1, 2, 3], [1, 3, 2]) ==
               {:error, {:index_mismatch, 1, {:not_equal, 2, 3}}}
    end

    test "wrong length fails with a length_mismatch, not a per-index error" do
      assert match([1, 2, 3], [1, 2]) == {:error, {:length_mismatch, 3, 2}}
      assert match([1, 2], [1, 2, 3]) == {:error, {:length_mismatch, 2, 3}}
    end

    test "an element-level mismatch reports its index and nested reason" do
      expected = [%{"id" => 1}, %{"id" => 2}]
      actual = [%{"id" => 1}, %{"id" => 99}]

      assert match(expected, actual) ==
               {:error, {:index_mismatch, 1, {:field_mismatch, "id", {:not_equal, 2, 99}}}}
    end
  end

  describe "ordered list matching: $expected / $unexpected as elements" do
    test "$expected is a positional wildcard: matches any value at that index" do
      assert match([1, "$expected", 3], [1, 2, 3]) == :ok
      assert match([1, "$expected", 3], [1, %{"anything" => "goes"}, 3]) == :ok
    end

    test "$expected still requires an element to actually be there" do
      assert match(["$expected", "$expected"], [1]) == {:error, {:length_mismatch, 2, 1}}
    end

    test "trailing $unexpected means the list ends there, exact prefix required" do
      assert match(["$expected", 2, "$expected", 4, "$unexpected"], [1, 2, 3, 4]) == :ok
    end

    test "trailing $unexpected still checks the values before it" do
      assert match([1, 2, "$unexpected"], [1, 99]) ==
               {:error, {:index_mismatch, 1, {:not_equal, 2, 99}}}
    end

    test "trailing $unexpected rejects a list with extra elements beyond the prefix" do
      assert match([1, 2, "$unexpected"], [1, 2, 3]) == {:error, {:length_mismatch, 2, 3}}
    end

    test "trailing $unexpected rejects a list shorter than the prefix" do
      assert match([1, 2, "$unexpected"], [1]) == {:error, {:length_mismatch, 2, 1}}
    end

    test "a lone $unexpected means the list must be empty" do
      assert match(["$unexpected"], []) == :ok
      assert match(["$unexpected"], [1]) == {:error, {:length_mismatch, 0, 1}}
    end

    test "$unexpected anywhere but last is a hard error, not guessed at" do
      assert match([1, "$unexpected", 3], [1, 2, 3]) ==
               {:error, {:invalid_unexpected_position, 1, 3}}
    end

    test "two $unexpected elements is also a hard error, at the first occurrence" do
      # find_index/2 finds the first occurrence, and a first occurrence can
      # never legitimately be the last element when a second one follows it,
      # so this falls into the same "not last" error as a single misplaced
      # $unexpected no special-casing needed for the duplicate case.
      assert match(["$unexpected", "$unexpected"], []) ==
               {:error, {:invalid_unexpected_position, 0, 2}}

      assert match([1, "$unexpected", "$unexpected"], [1]) ==
               {:error, {:invalid_unexpected_position, 1, 3}}
    end

    test "$expected/$unexpected as ordered-list elements are ordered-only, $contains ignores them" do
      expected = %{"$contains" => ["$expected"]}
      # inside $contains, "$expected" is just a literal string to match against
      assert match(expected, ["$expected", "other"]) == :ok

      assert match(expected, ["nope", "other"]) ==
               {:error, {:contains_item_not_found, 0, "$expected"}}
    end

    test "templating still resolves before these directives are interpreted" do
      expected = ["{{first}}", "$expected", "$unexpected"]
      assert match(expected, ["a", "b"], %{"first" => "a"}) == :ok
    end
  end

  describe "$contains" do
    test "a subset passes even with extra elements in actual" do
      expected = %{"$contains" => [1, 2]}
      assert match(expected, [1, 2, 3, 4]) == :ok
    end

    test "order doesn't matter" do
      expected = %{"$contains" => [3, 1]}
      assert match(expected, [1, 2, 3]) == :ok
    end

    test "a missing wanted item fails with its index" do
      expected = %{"$contains" => [1, 99]}
      assert match(expected, [1, 2, 3]) == {:error, {:contains_item_not_found, 1, 99}}
    end

    test "an empty wanted list trivially passes" do
      assert match(%{"$contains" => []}, [1, 2, 3]) == :ok
      assert match(%{"$contains" => []}, []) == :ok
    end

    test "nested directives inside a contains item" do
      expected = %{"$contains" => [%{"id" => "$expected"}]}
      actual = [%{"other" => true}, %{"id" => 42}]
      assert match(expected, actual) == :ok
    end

    test "nested directives inside a contains item that never matches" do
      expected = %{"$contains" => [%{"missing_field" => "$expected"}]}
      actual = [%{"id" => 42}]

      assert match(expected, actual) ==
               {:error, {:contains_item_not_found, 0, %{"missing_field" => "$expected"}}}
    end

    test "against a non-list actual is a type mismatch" do
      assert match(%{"$contains" => [1]}, "not a list") ==
               {:error, {:type_mismatch, :list_expected, "not a list"}}
    end

    test "documented greedy-matching limitation: a valid subset can be rejected" do
      # A genuine backtracking-need case, verified by hand: the first wanted
      # item (%{"id" => "$expected"}) can match EITHER actual element (both
      # have an "id" key); the second (%{"id" => 1}) can only match the
      # first actual element exactly. A valid assignment exists (first
      # wanted item -> second actual element, second wanted item -> first
      # actual element), but greedy processes wanted items in order and
      # picks the first satisfying candidate in remaining order: the first
      # wanted item consumes %{"id" => 1} (it's first in `actual` and any
      # id satisfies "$expected"), leaving only %{"id" => 2} for the second
      # wanted item, which requires exactly id 1 and fails. This is the
      # intentional, documented simplification (see moduledoc) not a
      # made-up scenario with no solution at all.
      expected = %{"$contains" => [%{"id" => "$expected"}, %{"id" => 1}]}
      actual = [%{"id" => 1}, %{"id" => 2}]

      assert match(expected, actual) == {:error, {:contains_item_not_found, 1, %{"id" => 1}}}
    end
  end

  describe "$regex" do
    test "a matching pattern passes" do
      assert match(%{"$regex" => "^ORD-\\d+$"}, "ORD-123") == :ok
    end

    test "a non-matching pattern fails" do
      assert match(%{"$regex" => "^ORD-\\d+$"}, "abc") ==
               {:error, {:regex_no_match, "^ORD-\\d+$", "abc"}}
    end

    test "an invalid pattern is a normal match error, not a crash" do
      assert {:error, {:invalid_regex, "(unclosed", _reason}} =
               match(%{"$regex" => "(unclosed"}, "abc")
    end

    test "applied to a non-string actual fails cleanly" do
      assert match(%{"$regex" => "^\\d+$"}, 42) ==
               {:error, {:regex_requires_string, "^\\d+$", 42}}
    end
  end

  describe "$mfa" do
    test "a function returning true passes" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "always_true"
      }

      assert match(%{"$mfa" => mfa}, "anything") == :ok
    end

    test "a function returning :ok passes" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "always_ok"
      }

      assert match(%{"$mfa" => mfa}, "anything") == :ok
    end

    test "a function returning false fails" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "always_false"
      }

      module = Maestro.Matchers.JsonMatchTest.Checks

      assert match(%{"$mfa" => mfa}, "anything") ==
               {:error, {:mfa_check_failed, module, :always_false}}
    end

    test "a function returning {:error, reason} fails with that reason" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "always_error"
      }

      module = Maestro.Matchers.JsonMatchTest.Checks

      assert match(%{"$mfa" => mfa}, "anything") ==
               {:error, {:mfa_check_failed, module, :always_error, :nope}}
    end

    test "a function returning something else is an invalid_mfa_result error" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "weird_result"
      }

      assert match(%{"$mfa" => mfa}, "anything") ==
               {:error, {:invalid_mfa_result, :not_a_valid_result}}
    end

    test "an unknown module never crashes the run" do
      mfa = %{"module" => "Maestro.DoesNotExistAtAll", "function" => "always_true"}

      assert match(%{"$mfa" => mfa}, "anything") ==
               {:error, {:mfa_module_not_found, "Maestro.DoesNotExistAtAll"}}
    end

    test "an unknown function on a real module never crashes the run" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "does_not_exist_anywhere"
      }

      assert match(%{"$mfa" => mfa}, "anything") ==
               {:error, {:mfa_function_not_found, "does_not_exist_anywhere"}}
    end

    test "a real function not exported at the given arity never crashes the run" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "always_true",
        "args" => ["unexpected", "extra", "args"]
      }

      assert {:error, {:mfa_not_exported, _mod, "always_true", 4}} =
               match(%{"$mfa" => mfa}, "anything")
    end

    test "a raising function is rescued, not a crash" do
      mfa = %{"module" => "Maestro.Matchers.JsonMatchTest.Checks", "function" => "boom"}
      module = Maestro.Matchers.JsonMatchTest.Checks

      assert match(%{"$mfa" => mfa}, "anything") ==
               {:error, {:mfa_raised, module, :boom, "kaboom"}}
    end

    test "args come from the already-interpolated expected tree" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "within_days",
        "args" => ["{{target_date}}", 2]
      }

      context = %{"target_date" => "2026-07-20"}
      assert match(%{"$mfa" => mfa}, "2026-07-22", context) == :ok
      assert match(%{"$mfa" => mfa}, "2026-08-01", context) != :ok
    end

    test "nested inside a $contains item" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "always_true"
      }

      expected = %{"$contains" => [%{"$mfa" => mfa}]}
      assert match(expected, ["anything", "else"]) == :ok
    end
  end

  describe "deep nesting combining several directives" do
    test "object containing an ordered list containing a contains list containing $expected" do
      expected = %{
        "id" => "$expected",
        "items" => [
          %{"sku" => "A", "tags" => %{"$contains" => ["red", %{"kind" => "$expected"}]}}
        ]
      }

      actual = %{
        "id" => 123,
        "items" => [
          %{"sku" => "A", "tags" => ["blue", "red", %{"kind" => "seasonal"}]}
        ]
      }

      assert match(expected, actual) == :ok
    end
  end

  describe "templating via context" do
    test "a plain {{placeholder}} in expected resolves before matching" do
      assert match(%{"id" => "{{order_id}}"}, %{"id" => "abc"}, %{"order_id" => "abc"}) == :ok
    end

    test "templating works at every nesting depth, including inside $contains" do
      expected = %{"$contains" => ["{{tag}}"]}
      assert match(expected, ["x", "urgent", "y"], %{"tag" => "urgent"}) == :ok
    end

    test "a missing interpolation key propagates as an error, not a silent pass-through" do
      assert match(%{"id" => "{{missing}}"}, %{"id" => "abc"}, %{}) ==
               {:error, {:missing_interpolation_key, "missing"}}
    end
  end

  describe "path selection" do
    test "path present and resolves checks only that sub-value" do
      assertion = %{expected: 42, path: "$.total"}
      assert JsonMatch.match(assertion, %{"total" => 42, "other" => "ignored"}, %{}) == :ok
    end

    test "path absent checks the whole actual" do
      assertion = %{expected: %{"total" => 42}}
      assert JsonMatch.match(assertion, %{"total" => 42}, %{}) == :ok
    end

    test "a path that doesn't resolve is its own error, with the underlying reason" do
      assertion = %{expected: 42, path: "$.missing"}

      assert JsonMatch.match(assertion, %{"total" => 42}, %{}) ==
               {:error, {:path_not_found, "$.missing", {:missing_key, "missing"}}}
    end
  end

  describe "type mismatches" do
    test "expected object, actual list" do
      assert match(%{"a" => 1}, [1, 2]) == {:error, {:type_mismatch, :object_expected, [1, 2]}}
    end

    test "expected object, actual scalar" do
      assert match(%{"a" => 1}, "not an object") ==
               {:error, {:type_mismatch, :object_expected, "not an object"}}
    end

    test "expected list, actual object" do
      assert match([1, 2], %{"a" => 1}) == {:error, {:type_mismatch, :list_expected, %{"a" => 1}}}
    end

    test "expected list, actual scalar" do
      assert match([1, 2], "not a list") ==
               {:error, {:type_mismatch, :list_expected, "not a list"}}
    end
  end
end
