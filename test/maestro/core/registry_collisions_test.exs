defmodule Maestro.Core.RegistryCollisionsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Maestro.Core.RegistryCollisions

  describe "warn_on_collisions/2" do
    test "logs a warning naming every module that registered the same name" do
      entries = [
        {"dup_name", Some.ModuleA},
        {"dup_name", Some.ModuleB},
        {"unique_name", Some.ModuleC}
      ]

      log =
        capture_log(fn ->
          assert :ok = RegistryCollisions.warn_on_collisions("SomeRegistry", entries)
        end)

      assert log =~ "SomeRegistry"
      assert log =~ "dup_name"
      assert log =~ "Some.ModuleA"
      assert log =~ "Some.ModuleB"
      refute log =~ "unique_name"
    end

    test "logs nothing when every name is registered by exactly one module" do
      entries = [{"a", Some.ModuleA}, {"b", Some.ModuleB}]

      log =
        capture_log(fn ->
          assert :ok = RegistryCollisions.warn_on_collisions("SomeRegistry", entries)
        end)

      assert log == ""
    end

    test "the same module registering the same name twice (duplicate discovery) is not a collision" do
      entries = [{"a", Some.ModuleA}, {"a", Some.ModuleA}]

      log =
        capture_log(fn ->
          assert :ok = RegistryCollisions.warn_on_collisions("SomeRegistry", entries)
        end)

      assert log == ""
    end
  end
end
