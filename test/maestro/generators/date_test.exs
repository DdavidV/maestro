defmodule Maestro.Generators.DateTest do
  use ExUnit.Case, async: true

  alias Maestro.Generators.Date, as: DateGenerator

  describe "generate/3, \"today\"" do
    test "zero-arg form returns today's ISO-8601 date" do
      expected = Date.to_iso8601(Date.utc_today())
      assert DateGenerator.generate("today", [], %{}) == {:ok, expected}
    end

    test "a positive integer offset returns that many days from today" do
      expected = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()
      assert DateGenerator.generate("today", [7], %{}) == {:ok, expected}
    end

    test "a negative integer offset returns that many days before today" do
      expected = Date.utc_today() |> Date.add(-3) |> Date.to_iso8601()
      assert DateGenerator.generate("today", [-3], %{}) == {:ok, expected}
    end

    test "a string-integer offset parses and behaves like the integer form" do
      expected = Date.utc_today() |> Date.add(5) |> Date.to_iso8601()
      assert DateGenerator.generate("today", ["5"], %{}) == {:ok, expected}
    end

    test "an invalid string offset is a clean error, not a raise" do
      assert DateGenerator.generate("today", ["not-a-number"], %{}) ==
               {:error, {:invalid_offset, "not-a-number"}}
    end

    test "an invalid args shape is a clean error, not a raise" do
      assert DateGenerator.generate("today", [1, 2], %{}) == {:error, {:invalid_args, [1, 2]}}
      assert DateGenerator.generate("today", [%{}], %{}) == {:error, {:invalid_args, [%{}]}}
    end
  end
end
