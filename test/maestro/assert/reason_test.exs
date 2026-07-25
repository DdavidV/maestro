defmodule Maestro.Assert.ReasonTest do
  use ExUnit.Case, async: true

  alias Maestro.Assert.Reason

  describe "new/4" do
    test "builds a struct with all fields" do
      assert Reason.new(:not_equal, 1, 2, "$.a") == %Reason{
               reason: :not_equal,
               expected: 1,
               actual: 2,
               path: "$.a"
             }
    end

    test "expected/actual/path default to nil" do
      assert Reason.new(:matcher_not_found) == %Reason{
               reason: :matcher_not_found,
               expected: nil,
               actual: nil,
               path: nil
             }
    end

    test "reason must be a non-nil atom" do
      assert_raise FunctionClauseError, fn -> Reason.new(nil) end
      assert_raise FunctionClauseError, fn -> Reason.new("not_an_atom") end
    end
  end

  describe "@enforce_keys" do
    test "reason is required when building the struct literal" do
      assert_raise ArgumentError, fn ->
        Code.eval_string("%Maestro.Assert.Reason{}")
      end
    end
  end
end
