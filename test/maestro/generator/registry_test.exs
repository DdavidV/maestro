defmodule Maestro.Generator.RegistryTest do
  use ExUnit.Case, async: false

  alias Maestro.Generator.Registry

  setup do
    :ok = Registry.load!()
    :ok
  end

  describe "fetch/1" do
    test "finds the built-in today generator" do
      assert Registry.fetch("today") == {:ok, Maestro.Generators.Date}
    end

    test "finds every name a `use Maestro.Generator` module registers, no explicit registration" do
      assert Registry.fetch("test_counter") == {:ok, Maestro.TestGenerator}
      assert Registry.fetch("test_echo_args") == {:ok, Maestro.TestGenerator}
    end

    test "multiple names from the same module resolve to that same module" do
      assert {:ok, module} = Registry.fetch("test_counter")
      assert {:ok, ^module} = Registry.fetch("test_echo_args")
    end

    test "returns {:error, :not_found} for an unregistered name" do
      assert Registry.fetch("does_not_exist") == {:error, :not_found}
    end
  end

  describe "load!/0" do
    test "is safe to call more than once" do
      assert :ok = Registry.load!()
      assert Registry.fetch("today") == {:ok, Maestro.Generators.Date}
    end
  end
end
