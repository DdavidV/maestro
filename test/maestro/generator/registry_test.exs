defmodule Maestro.Generator.RegistryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

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

  describe "warn_on_collisions/1" do
    test "logs a warning naming every module that registered the same name" do
      entries = [
        {"dup_name", Some.ModuleA},
        {"dup_name", Some.ModuleB},
        {"unique_name", Some.ModuleC}
      ]

      log =
        capture_log(fn ->
          assert :ok = Registry.warn_on_collisions(entries)
        end)

      assert log =~ "dup_name"
      assert log =~ "Some.ModuleA"
      assert log =~ "Some.ModuleB"
      refute log =~ "unique_name"
    end

    test "logs nothing when every name is registered by exactly one module" do
      entries = [{"a", Some.ModuleA}, {"b", Some.ModuleB}]

      log =
        capture_log(fn ->
          assert :ok = Registry.warn_on_collisions(entries)
        end)

      assert log == ""
    end

    test "the same module registering the same name twice (duplicate discovery) is not a collision" do
      entries = [{"a", Some.ModuleA}, {"a", Some.ModuleA}]

      log =
        capture_log(fn ->
          assert :ok = Registry.warn_on_collisions(entries)
        end)

      assert log == ""
    end
  end
end
