defmodule Maestro.Core.AssertRunnerTest do
  use ExUnit.Case, async: false

  alias Maestro.Assert.AssertionResult
  alias Maestro.Assert.Reason
  alias Maestro.Assert.Registry, as: AssertRegistry
  alias Maestro.Core.AssertRunner

  setup do
    :ok = AssertRegistry.load!()
    :ok
  end

  describe "run_assertions/3" do
    test "an empty list is a no-op" do
      assert AssertRunner.run_assertions([], %{"a" => 1}, %{}) == {:ok, []}
    end

    test "all assertions passing yields :ok, each result carrying the assertion and actual too" do
      assertions = [
        %{matcher: "test_matcher_always_ok", expected: nil},
        %{matcher: "test_matcher_always_ok", expected: nil}
      ]

      actual = %{"a" => 1}

      assert AssertRunner.run_assertions(assertions, actual, %{}) ==
               {:ok,
                [
                  %AssertionResult{
                    status: :ok,
                    reasons: [],
                    assertion: Enum.at(assertions, 0),
                    actual: actual
                  },
                  %AssertionResult{
                    status: :ok,
                    reasons: [],
                    assertion: Enum.at(assertions, 1),
                    actual: actual
                  }
                ]}
    end

    test "one failing assertion makes the aggregate :error, both results recorded" do
      assertions = [
        %{matcher: "test_matcher_always_ok", expected: nil},
        %{"should_fail" => true, matcher: "test_matcher", expected: nil}
      ]

      assert {:error, results} = AssertRunner.run_assertions(assertions, %{"a" => 1}, %{})
      assert [%AssertionResult{status: :ok}, %AssertionResult{status: :error}] = results
    end

    test "an unregistered matcher name is an assertion-level error, not a crash" do
      assertion = %{matcher: "does_not_exist", expected: 1}
      actual = %{"a" => 1}

      assert AssertRunner.run_assertions([assertion], actual, %{}) ==
               {:error,
                [
                  %AssertionResult{
                    status: :error,
                    reasons: [
                      %Reason{reason: :matcher_not_found, expected: "does_not_exist", actual: nil}
                    ],
                    assertion: assertion,
                    actual: actual
                  }
                ]}
    end

    test "assertion/actual/context are passed through to the matcher unchanged" do
      assertion = %{"should_fail" => true, matcher: "test_matcher", expected: 42, path: "$.total"}
      actual = %{"total" => 42}
      context = %{"seed" => "abc"}

      assert {:error, [%AssertionResult{reasons: [reason]}]} =
               AssertRunner.run_assertions([assertion], actual, context)

      assert %Reason{
               reason: :test_matcher_saw,
               expected: ^assertion,
               actual: {^assertion, ^actual, ^context}
             } =
               reason
    end

    test "a matcher reporting several reasons is passed through as a multi-entry list" do
      assertion = %{matcher: "json_match", expected: %{"a" => 1, "b" => 2}}
      actual = %{"a" => 9, "b" => 9}

      assert {:error, [%AssertionResult{status: :error, reasons: reasons}]} =
               AssertRunner.run_assertions([assertion], actual, %{})

      assert length(reasons) == 2
    end
  end
end
