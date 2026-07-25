defmodule Maestro.Core.SafeMFATest do
  use ExUnit.Case, async: true

  alias Maestro.Core.SafeMFA

  defmodule Checks do
    def add(a, b), do: a + b
    def boom(_a), do: raise("kaboom")
  end

  describe "apply/3" do
    test "resolves and calls the function, returning the resolved module/function/result" do
      assert SafeMFA.apply("Maestro.Core.SafeMFATest.Checks", "add", [1, 2]) ==
               {:ok, Checks, :add, 3}
    end

    test "an unknown module never crashes" do
      assert SafeMFA.apply("Does.Not.Exist.At.All", "add", [1, 2]) ==
               {:error, {:mfa_module_not_found, "Does.Not.Exist.At.All"}}
    end

    test "an unknown function on a real module never crashes" do
      assert SafeMFA.apply("Maestro.Core.SafeMFATest.Checks", "does_not_exist", []) ==
               {:error, {:mfa_function_not_found, "does_not_exist"}}
    end

    test "a real function not exported at the given arity never crashes" do
      assert SafeMFA.apply("Maestro.Core.SafeMFATest.Checks", "add", [1, 2, 3]) ==
               {:error, {:mfa_not_exported, "Maestro.Core.SafeMFATest.Checks", "add", 3}}
    end

    test "a raising function is rescued, not a crash" do
      assert SafeMFA.apply("Maestro.Core.SafeMFATest.Checks", "boom", [1]) ==
               {:error, {:mfa_raised, Checks, :boom, "kaboom"}}
    end

    test "an unknown function name never becomes a new atom" do
      random = "maestro_safe_mfa_probe_#{System.unique_integer([:positive])}"

      assert SafeMFA.apply("Maestro.Core.SafeMFATest.Checks", random, []) ==
               {:error, {:mfa_function_not_found, random}}

      assert_raise ArgumentError, fn -> String.to_existing_atom(random) end
    end
  end
end
