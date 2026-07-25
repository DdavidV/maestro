defmodule Maestro.Matchers.JsonMatchTest do
  use ExUnit.Case, async: true

  alias Maestro.Assert.Reason
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

  defp reasons(expected, actual, context \\ %{}) do
    assert {:error, reasons} = match(expected, actual, context)
    reasons
  end

  defp reason(expected, actual, context \\ %{}) do
    assert [reason] = reasons(expected, actual, context)
    reason
  end

  describe "scalar equality" do
    test "matching values of every scalar type pass" do
      assert match("abc", "abc") == :ok
      assert match(42, 42) == :ok
      assert match(true, true) == :ok
      assert match(nil, nil) == :ok
    end

    test "mismatching scalars fail with the values" do
      assert reason("abc", "xyz") == %Reason{
               reason: :not_equal,
               expected: "abc",
               actual: "xyz",
               path: nil
             }

      assert reason(42, 43) == %Reason{reason: :not_equal, expected: 42, actual: 43, path: nil}

      assert reason(true, false) == %Reason{
               reason: :not_equal,
               expected: true,
               actual: false,
               path: nil
             }
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

    test "one mismatching field fails, tagged with its path" do
      expected = %{"id" => 1, "name" => "alice"}
      actual = %{"id" => 1, "name" => "bob"}

      assert reason(expected, actual) == %Reason{
               reason: :not_equal,
               expected: "alice",
               actual: "bob",
               path: ".name"
             }
    end

    test "a missing expected key fails" do
      expected = %{"id" => 1, "name" => "alice"}
      actual = %{"id" => 1}

      assert reason(expected, actual) == %Reason{
               reason: :expected_key_missing,
               expected: "alice",
               actual: nil,
               path: ".name"
             }
    end

    test "multiple independently-wrong fields are all reported, not just the first" do
      expected = %{"a" => 1, "b" => 2, "c" => 3}
      actual = %{"a" => 9, "b" => 2, "c" => 9}

      assert reasons(expected, actual) == [
               %Reason{reason: :not_equal, expected: 1, actual: 9, path: ".a"},
               %Reason{reason: :not_equal, expected: 3, actual: 9, path: ".c"}
             ]
    end
  end

  describe "$expected / $unexpected" do
    test "$expected: key present with any value passes" do
      assert match(%{"token" => "$expected"}, %{"token" => "abc123"}) == :ok
      assert match(%{"token" => "$expected"}, %{"token" => nil}) == :ok
    end

    test "$expected: key absent fails" do
      assert reason(%{"token" => "$expected"}, %{}) == %Reason{
               reason: :expected_key_missing,
               expected: "$expected",
               actual: nil,
               path: ".token"
             }
    end

    test "$unexpected: key absent passes" do
      assert match(%{"internal" => "$unexpected"}, %{"id" => 1}) == :ok
    end

    test "$unexpected: key present fails, even when its value is null" do
      assert reason(%{"internal" => "$unexpected"}, %{"internal" => "leaked"}) == %Reason{
               reason: :unexpected_key_present,
               expected: "$unexpected",
               actual: "leaked",
               path: ".internal"
             }

      assert reason(%{"internal" => "$unexpected"}, %{"internal" => nil}) == %Reason{
               reason: :unexpected_key_present,
               expected: "$unexpected",
               actual: nil,
               path: ".internal"
             }
    end
  end

  describe "$_ closed-object directive" do
    test "no extra keys beyond those named passes" do
      expected = %{"id" => 1, "$_" => "$unexpected"}
      assert match(expected, %{"id" => 1}) == :ok
    end

    test "one extra key fails" do
      expected = %{"id" => 1, "$_" => "$unexpected"}
      actual = %{"id" => 1, "extra" => "field"}

      assert reason(expected, actual) == %Reason{
               reason: :unexpected_extra_keys,
               expected: ["id"],
               actual: ["extra", "id"],
               path: nil
             }
    end

    test "closing applies at nested depth too, not just the top level" do
      expected = %{"user" => %{"id" => 1, "$_" => "$unexpected"}}
      actual = %{"user" => %{"id" => 1, "secret" => "leaked"}}

      assert reason(expected, actual) == %Reason{
               reason: :unexpected_extra_keys,
               expected: ["id"],
               actual: ["id", "secret"],
               path: ".user"
             }
    end

    test "an invalid $_ pairing is a hard error, not silently ignored" do
      expected = %{"id" => 1, "$_" => true}

      assert reason(expected, %{"id" => 1}) == %Reason{
               reason: :invalid_closed_object_directive,
               expected: true,
               actual: nil,
               path: nil
             }
    end
  end

  describe "ordered list matching (bare arrays)" do
    test "exact match in order passes" do
      assert match([1, 2, 3], [1, 2, 3]) == :ok
    end

    test "wrong order reports every mismatching index" do
      assert reasons([1, 2, 3], [1, 3, 2]) == [
               %Reason{reason: :not_equal, expected: 2, actual: 3, path: "[1]"},
               %Reason{reason: :not_equal, expected: 3, actual: 2, path: "[2]"}
             ]
    end

    test "wrong length fails with a length_mismatch, alongside any paired-element mismatches" do
      assert reason([1, 2, 3], [1, 2]) == %Reason{
               reason: :length_mismatch,
               expected: 3,
               actual: 2,
               path: nil
             }

      assert reason([1, 2], [1, 2, 3]) == %Reason{
               reason: :length_mismatch,
               expected: 2,
               actual: 3,
               path: nil
             }
    end

    test "an element-level mismatch reports its index and nested path" do
      expected = [%{"id" => 1}, %{"id" => 2}]
      actual = [%{"id" => 1}, %{"id" => 99}]

      assert reason(expected, actual) == %Reason{
               reason: :not_equal,
               expected: 2,
               actual: 99,
               path: "[1].id"
             }
    end

    test "multiple mismatching indices are all reported" do
      assert reasons([1, 2, 3], [9, 2, 9]) == [
               %Reason{reason: :not_equal, expected: 1, actual: 9, path: "[0]"},
               %Reason{reason: :not_equal, expected: 3, actual: 9, path: "[2]"}
             ]
    end
  end

  describe "ordered list matching: $expected / $unexpected as elements" do
    test "$expected is a positional wildcard: matches any value at that index" do
      assert match([1, "$expected", 3], [1, 2, 3]) == :ok
      assert match([1, "$expected", 3], [1, %{"anything" => "goes"}, 3]) == :ok
    end

    test "$expected still requires an element to actually be there" do
      assert reason(["$expected", "$expected"], [1]) == %Reason{
               reason: :length_mismatch,
               expected: 2,
               actual: 1,
               path: nil
             }
    end

    test "trailing $unexpected means the list ends there, exact prefix required" do
      assert match(["$expected", 2, "$expected", 4, "$unexpected"], [1, 2, 3, 4]) == :ok
    end

    test "trailing $unexpected still checks the values before it" do
      assert reason([1, 2, "$unexpected"], [1, 99]) == %Reason{
               reason: :not_equal,
               expected: 2,
               actual: 99,
               path: "[1]"
             }
    end

    test "trailing $unexpected rejects a list with extra elements beyond the prefix" do
      assert reason([1, 2, "$unexpected"], [1, 2, 3]) == %Reason{
               reason: :length_mismatch,
               expected: 2,
               actual: 3,
               path: nil
             }
    end

    test "trailing $unexpected rejects a list shorter than the prefix" do
      assert reason([1, 2, "$unexpected"], [1]) == %Reason{
               reason: :length_mismatch,
               expected: 2,
               actual: 1,
               path: nil
             }
    end

    test "a lone $unexpected means the list must be empty" do
      assert match(["$unexpected"], []) == :ok

      assert reason(["$unexpected"], [1]) == %Reason{
               reason: :length_mismatch,
               expected: 0,
               actual: 1,
               path: nil
             }
    end

    test "$unexpected anywhere but last is a hard error, not guessed at" do
      assert reason([1, "$unexpected", 3], [1, 2, 3]) == %Reason{
               reason: :invalid_unexpected_position,
               expected: 1,
               actual: 3,
               path: nil
             }
    end

    test "two $unexpected elements is also a hard error, at the first occurrence" do
      # find_index/2 finds the first occurrence, and a first occurrence can
      # never legitimately be the last element when a second one follows it,
      # so this falls into the same "not last" error as a single misplaced
      # $unexpected no special-casing needed for the duplicate case.
      assert reason(["$unexpected", "$unexpected"], []) == %Reason{
               reason: :invalid_unexpected_position,
               expected: 0,
               actual: 2,
               path: nil
             }

      assert reason([1, "$unexpected", "$unexpected"], [1]) == %Reason{
               reason: :invalid_unexpected_position,
               expected: 1,
               actual: 3,
               path: nil
             }
    end

    test "$expected/$unexpected as ordered-list elements are ordered-only, $contains ignores them" do
      expected = %{"$contains" => ["$expected"]}
      # inside $contains, "$expected" is just a literal string to match against
      assert match(expected, ["$expected", "other"]) == :ok

      assert reason(expected, ["nope", "other"]) == %Reason{
               reason: :contains_item_not_found,
               expected: "$expected",
               actual: ["nope", "other"],
               path: nil
             }
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

    test "a missing wanted item fails" do
      expected = %{"$contains" => [1, 99]}

      assert reason(expected, [1, 2, 3]) == %Reason{
               reason: :contains_item_not_found,
               expected: 99,
               actual: [1, 2, 3],
               path: nil
             }
    end

    test "several missing wanted items are all reported" do
      expected = %{"$contains" => [98, 99]}

      assert reasons(expected, [1, 2, 3]) == [
               %Reason{
                 reason: :contains_item_not_found,
                 expected: 98,
                 actual: [1, 2, 3],
                 path: nil
               },
               %Reason{
                 reason: :contains_item_not_found,
                 expected: 99,
                 actual: [1, 2, 3],
                 path: nil
               }
             ]
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

      assert reason(expected, actual) == %Reason{
               reason: :contains_item_not_found,
               expected: %{"missing_field" => "$expected"},
               actual: actual,
               path: nil
             }
    end

    test "against a non-list actual is a type mismatch" do
      assert reason(%{"$contains" => [1]}, "not a list") == %Reason{
               reason: :list_expected,
               expected: nil,
               actual: "not a list",
               path: nil
             }
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

      assert reason(expected, actual) == %Reason{
               reason: :contains_item_not_found,
               expected: %{"id" => 1},
               actual: actual,
               path: nil
             }
    end
  end

  describe "$excludes" do
    test "passes when none of the excluded items appear in actual" do
      expected = %{"$excludes" => [99, 100]}
      assert match(expected, [1, 2, 3]) == :ok
    end

    test "fails with the excluded item and where it was found" do
      expected = %{"$excludes" => [1, 2]}

      assert reason(expected, [5, 2, 7]) == %Reason{
               reason: :excluded_item_found,
               expected: 2,
               actual: 2,
               path: nil
             }
    end

    test "an empty excluded list trivially passes" do
      assert match(%{"$excludes" => []}, [1, 2, 3]) == :ok
      assert match(%{"$excludes" => []}, []) == :ok
    end

    test "matches structurally, not just by literal equality" do
      expected = %{"$excludes" => [%{"key" => "val"}]}
      assert match(expected, [%{"key" => "other"}, %{"other" => "field"}]) == :ok

      assert reason(expected, [%{"key" => "val", "extra" => "ignored"}]) == %Reason{
               reason: :excluded_item_found,
               expected: %{"key" => "val"},
               actual: %{"key" => "val", "extra" => "ignored"},
               path: nil
             }
    end

    test "against a non-list actual is a type mismatch" do
      assert reason(%{"$excludes" => [1]}, "not a list") == %Reason{
               reason: :list_expected,
               expected: nil,
               actual: "not a list",
               path: nil
             }
    end

    test "nested directives inside an excluded item still apply" do
      expected = %{"$excludes" => [%{"id" => "$expected"}]}
      # any object with an "id" key is excluded, so this actual violates it
      assert reason(expected, [%{"id" => 1}]) == %Reason{
               reason: :excluded_item_found,
               expected: %{"id" => "$expected"},
               actual: %{"id" => 1},
               path: nil
             }

      assert match(expected, [%{"name" => "no id here"}]) == :ok
    end

    test "templating resolves before exclusion is checked" do
      expected = %{"$excludes" => ["{{banned}}"]}
      assert match(expected, ["a", "b"], %{"banned" => "c"}) == :ok

      assert reason(expected, ["a", "b"], %{"banned" => "a"}) == %Reason{
               reason: :excluded_item_found,
               expected: "a",
               actual: "a",
               path: nil
             }
    end
  end

  describe "$length" do
    test "bare integer is an exact-length check" do
      assert match(%{"$length" => 3}, [1, 2, 3]) == :ok

      assert reason(%{"$length" => 3}, [1, 2]) == %Reason{
               reason: :length_not_equal,
               expected: 3,
               actual: 2,
               path: nil
             }
    end

    test "$gt: strictly greater than" do
      assert match(%{"$length" => %{"$gt" => 2}}, [1, 2, 3]) == :ok

      assert reason(%{"$length" => %{"$gt" => 2}}, [1, 2]) == %Reason{
               reason: :length_not_greater_than,
               expected: 2,
               actual: 2,
               path: nil
             }
    end

    test "$lt: strictly less than" do
      assert match(%{"$length" => %{"$lt" => 3}}, [1, 2]) == :ok

      assert reason(%{"$length" => %{"$lt" => 3}}, [1, 2, 3]) == %Reason{
               reason: :length_not_less_than,
               expected: 3,
               actual: 3,
               path: nil
             }
    end

    test "$between: inclusive on both ends" do
      assert match(%{"$length" => %{"$between" => [2, 4]}}, [1, 2]) == :ok
      assert match(%{"$length" => %{"$between" => [2, 4]}}, [1, 2, 3, 4]) == :ok

      assert reason(%{"$length" => %{"$between" => [2, 4]}}, [1]) == %Reason{
               reason: :length_not_between,
               expected: [2, 4],
               actual: 1,
               path: nil
             }

      assert reason(%{"$length" => %{"$between" => [2, 4]}}, [1, 2, 3, 4, 5]) == %Reason{
               reason: :length_not_between,
               expected: [2, 4],
               actual: 5,
               path: nil
             }
    end

    test "against a non-list actual is a type mismatch" do
      assert reason(%{"$length" => 3}, "not a list") == %Reason{
               reason: :list_expected,
               expected: nil,
               actual: "not a list",
               path: nil
             }
    end

    test "a malformed spec is a hard error, not guessed at" do
      assert reason(%{"$length" => %{"$foo" => 1}}, [1]) == %Reason{
               reason: :invalid_length_directive,
               expected: %{"$foo" => 1},
               actual: nil,
               path: nil
             }

      assert reason(%{"$length" => "three"}, [1]) == %Reason{
               reason: :invalid_length_directive,
               expected: "three",
               actual: nil,
               path: nil
             }
    end

    test "does not compose with $contains/$excludes in the same wrapper" do
      # a map with more than one key isn't a recognized single-key
      # directive, so it falls through to a literal object match, which
      # then fails against a list actual this is documented behavior,
      # not a bug: checking both length and contents needs two `assert`
      # entries with the same `path`, not one combined expected value.
      expected = %{"$length" => 3, "$contains" => [1]}

      assert reason(expected, [1, 2, 3]) == %Reason{
               reason: :object_expected,
               expected: expected,
               actual: [1, 2, 3],
               path: nil
             }
    end

    test "checking length and contents of the same list via two assert entries" do
      response = %{"items" => ["a", "b"]}

      length_check = %{expected: %{"$length" => %{"$between" => [1, 5]}}, path: "$.items"}
      contains_check = %{expected: %{"$contains" => ["a"]}, path: "$.items"}

      assert JsonMatch.match(length_check, response, %{}) == :ok
      assert JsonMatch.match(contains_check, response, %{}) == :ok
    end

    test "templating resolves before length is checked" do
      expected = %{"$length" => %{"$gt" => "{{min_count}}"}}
      assert match(expected, [1, 2, 3], %{"min_count" => 2}) == :ok

      assert reason(expected, [1], %{"min_count" => 2}) == %Reason{
               reason: :length_not_greater_than,
               expected: 2,
               actual: 1,
               path: nil
             }
    end
  end

  describe "$regex" do
    test "a matching pattern passes" do
      assert match(%{"$regex" => "^ORD-\\d+$"}, "ORD-123") == :ok
    end

    test "a non-matching pattern fails" do
      assert reason(%{"$regex" => "^ORD-\\d+$"}, "abc") == %Reason{
               reason: :regex_no_match,
               expected: "^ORD-\\d+$",
               actual: "abc",
               path: nil
             }
    end

    test "an invalid pattern is a normal match error, not a crash" do
      assert %Reason{reason: :invalid_regex, expected: "(unclosed", actual: _reason} =
               reason(%{"$regex" => "(unclosed"}, "abc")
    end

    test "applied to a non-string actual fails cleanly" do
      assert reason(%{"$regex" => "^\\d+$"}, 42) == %Reason{
               reason: :invalid_regex,
               expected: "^\\d+$",
               actual: 42,
               path: nil
             }
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

      assert reason(%{"$mfa" => mfa}, "anything") == %Reason{
               reason: :mfa_check_failed,
               expected: {module, :always_false},
               actual: "anything",
               path: nil
             }
    end

    test "a function returning {:error, reason} fails with that reason" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "always_error"
      }

      module = Maestro.Matchers.JsonMatchTest.Checks

      assert reason(%{"$mfa" => mfa}, "anything") == %Reason{
               reason: :mfa_check_failed,
               expected: {module, :always_error},
               actual: :nope,
               path: nil
             }
    end

    test "a function returning something else is an invalid_mfa_result error" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "weird_result"
      }

      assert reason(%{"$mfa" => mfa}, "anything") == %Reason{
               reason: :invalid_mfa_result,
               expected: mfa,
               actual: :not_a_valid_result,
               path: nil
             }
    end

    test "an unknown module never crashes the run" do
      mfa = %{"module" => "Maestro.DoesNotExistAtAll", "function" => "always_true"}

      assert reason(%{"$mfa" => mfa}, "anything") == %Reason{
               reason: :mfa_error,
               expected: mfa,
               actual: {:mfa_module_not_found, "Maestro.DoesNotExistAtAll"},
               path: nil
             }
    end

    test "an unknown function on a real module never crashes the run" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "does_not_exist_anywhere"
      }

      assert reason(%{"$mfa" => mfa}, "anything") == %Reason{
               reason: :mfa_error,
               expected: mfa,
               actual: {:mfa_function_not_found, "does_not_exist_anywhere"},
               path: nil
             }
    end

    test "a real function not exported at the given arity never crashes the run" do
      mfa = %{
        "module" => "Maestro.Matchers.JsonMatchTest.Checks",
        "function" => "always_true",
        "args" => ["unexpected", "extra", "args"]
      }

      assert %Reason{
               reason: :mfa_error,
               expected: ^mfa,
               actual: {:mfa_not_exported, _mod, "always_true", 4}
             } =
               reason(%{"$mfa" => mfa}, "anything")
    end

    test "a raising function is rescued, not a crash" do
      mfa = %{"module" => "Maestro.Matchers.JsonMatchTest.Checks", "function" => "boom"}
      module = Maestro.Matchers.JsonMatchTest.Checks

      assert reason(%{"$mfa" => mfa}, "anything") == %Reason{
               reason: :mfa_error,
               expected: mfa,
               actual: {:mfa_raised, module, :boom, "kaboom"},
               path: nil
             }
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
      assert reason(%{"id" => "{{missing}}"}, %{"id" => "abc"}, %{}) == %Reason{
               reason: :interpolation_failed,
               expected: "missing",
               actual: nil,
               path: nil
             }
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

    test "a path that doesn't resolve is its own error" do
      assertion = %{expected: 42, path: "$.missing"}

      assert JsonMatch.match(assertion, %{"total" => 42}, %{}) ==
               {:error,
                [
                  %Reason{
                    reason: :path_not_found,
                    expected: "$.missing",
                    actual: nil,
                    path: nil
                  }
                ]}
    end
  end

  describe "type mismatches" do
    test "expected object, actual list" do
      assert reason(%{"a" => 1}, [1, 2]) == %Reason{
               reason: :object_expected,
               expected: %{"a" => 1},
               actual: [1, 2],
               path: nil
             }
    end

    test "expected object, actual scalar" do
      assert reason(%{"a" => 1}, "not an object") == %Reason{
               reason: :object_expected,
               expected: %{"a" => 1},
               actual: "not an object",
               path: nil
             }
    end

    test "expected list, actual object" do
      assert reason([1, 2], %{"a" => 1}) == %Reason{
               reason: :list_expected,
               expected: [1, 2],
               actual: %{"a" => 1},
               path: nil
             }
    end

    test "expected list, actual scalar" do
      assert reason([1, 2], "not a list") == %Reason{
               reason: :list_expected,
               expected: [1, 2],
               actual: "not a list",
               path: nil
             }
    end
  end
end
