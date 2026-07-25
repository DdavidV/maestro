defmodule Maestro.Assert.AssertionResultTest do
  use ExUnit.Case, async: true

  alias Maestro.Assert.AssertionResult

  describe "@enforce_keys" do
    test "status, assertion, and actual are required" do
      assert_raise ArgumentError, fn ->
        Code.eval_string("%Maestro.Assert.AssertionResult{}")
      end
    end
  end

  describe "struct shape" do
    test "reasons defaults to an empty list" do
      result = %AssertionResult{status: :ok, assertion: %{matcher: "m"}, actual: 1}
      assert result.reasons == []
    end
  end
end
