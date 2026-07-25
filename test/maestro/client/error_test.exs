defmodule Maestro.Client.ErrorTest do
  use ExUnit.Case, async: true

  alias Maestro.Client.Error

  describe "new/3" do
    test "builds a struct with all fields" do
      assert Error.new(:send, :send_failed, :boom) == %Error{
               stage: :send,
               reason: :send_failed,
               details: :boom
             }
    end

    test "details defaults to nil" do
      assert Error.new(:client_lookup, :client_not_found) == %Error{
               stage: :client_lookup,
               reason: :client_not_found,
               details: nil
             }
    end

    test "reason must be a non-nil atom" do
      assert_raise FunctionClauseError, fn -> Error.new(:send, nil) end
      assert_raise FunctionClauseError, fn -> Error.new(:send, "not_an_atom") end
    end
  end

  describe "@enforce_keys" do
    test "stage and reason are required" do
      assert_raise ArgumentError, fn ->
        Code.eval_string("%Maestro.Client.Error{}")
      end
    end
  end
end
