defmodule Maestro.Assert.RegistryTest do
  use ExUnit.Case, async: false

  alias Maestro.Assert.Registry

  setup do
    :ok = Registry.load!()
    :ok
  end

  describe "fetch/1" do
    test "finds the built-in json_match matcher" do
      assert Registry.fetch("json_match") == {:ok, Maestro.Matchers.JsonMatch}
    end

    test "finds a matcher discovered via `use Maestro.Assert.Matcher`, no explicit registration" do
      assert Registry.fetch("test_matcher") == {:ok, Maestro.TestMatcher}
    end

    test "multiple matchers register independently" do
      assert Registry.fetch("test_matcher") == {:ok, Maestro.TestMatcher}
      assert Registry.fetch("test_matcher_always_ok") == {:ok, Maestro.TestMatcherAlwaysOk}
    end

    test "returns {:error, :not_found} for an unregistered name" do
      assert Registry.fetch("does_not_exist") == {:error, :not_found}
    end
  end

  describe "load!/0" do
    test "is safe to call more than once" do
      assert :ok = Registry.load!()
      assert Registry.fetch("json_match") == {:ok, Maestro.Matchers.JsonMatch}
    end
  end
end
