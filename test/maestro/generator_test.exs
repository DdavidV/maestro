defmodule Maestro.GeneratorTest do
  use ExUnit.Case, async: true

  alias Maestro.TestGenerator

  describe "__maestro_generators__/0" do
    test "lists every generated_data block registered in the module" do
      names = TestGenerator.__maestro_generators__() |> Enum.map(&elem(&1, 0))

      assert "test_counter" in names
      assert "test_echo_args" in names
      assert "test_always_fails" in names
      assert "test_always_raises" in names
    end
  end

  describe "generate/3" do
    test "dispatches to the block registered under that name" do
      assert {:ok, [1, "two", 3]} = TestGenerator.generate("test_echo_args", [1, "two", 3], %{})
    end

    test "each call produces a fresh value, not a cached one" do
      {:ok, first} = TestGenerator.generate("test_counter", [], %{})
      {:ok, second} = TestGenerator.generate("test_counter", [], %{})

      assert first != second
    end

    test "an error return is passed through unchanged" do
      assert TestGenerator.generate("test_always_fails", [], %{}) == {:error, :always_fails}
    end

    test "an unregistered name within a module that has others is :not_found" do
      assert TestGenerator.generate("does_not_exist", [], %{}) == {:error, :not_found}
    end
  end

  describe "duplicate names within a single module" do
    test "is a compile error, not a silent shadow" do
      assert_raise CompileError, ~r/registers the same generated_data name more than once/, fn ->
        Code.compile_string("""
        defmodule Maestro.GeneratorTest.DuplicateWithinModule do
          use Maestro.Generator

          generated_data "dup", _args, _context do
            {:ok, 1}
          end

          generated_data "dup", _args, _context do
            {:ok, 2}
          end
        end
        """)
      end
    end
  end
end
