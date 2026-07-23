defmodule Maestro.Core.AssertRunnerTest do
  use ExUnit.Case, async: false

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
                  %{
                    status: :ok,
                    reason: nil,
                    assertion: Enum.at(assertions, 0),
                    actual: actual
                  },
                  %{
                    status: :ok,
                    reason: nil,
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
      assert [%{status: :ok}, %{status: :error}] = results
    end

    test "an unregistered matcher name is an assertion-level error, not a crash" do
      assertion = %{matcher: "does_not_exist", expected: 1}
      actual = %{"a" => 1}

      assert AssertRunner.run_assertions([assertion], actual, %{}) ==
               {:error,
                [
                  %{
                    status: :error,
                    reason: :not_found,
                    assertion: assertion,
                    actual: actual
                  }
                ]}
    end

    test "assertion/actual/context are passed through to the matcher unchanged" do
      assertion = %{"should_fail" => true, matcher: "test_matcher", expected: 42, path: "$.total"}
      actual = %{"total" => 42}
      context = %{"seed" => "abc"}

      assert {:error, [%{reason: reason}]} =
               AssertRunner.run_assertions([assertion], actual, context)

      assert {:test_matcher_saw, ^assertion, ^actual, ^context} = reason
    end
  end
end
