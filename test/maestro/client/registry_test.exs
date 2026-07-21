defmodule Maestro.Client.RegistryTest do
  use ExUnit.Case, async: false

  alias Maestro.Client.Registry

  setup do
    :ok = Registry.load!()
    :ok
  end

  describe "fetch/2" do
    test "finds a client discovered via `use Maestro.Client`, no explicit registration" do
      assert {:ok, %{module: Maestro.TestClient, state: state}} = Registry.fetch("test_client")
      assert is_pid(state)
    end

    test "a client without init_client/1 still registers, with a nil state" do
      assert {:ok, %{module: Maestro.TestClientNoOptional, state: nil}} =
               Registry.fetch("test_client_no_optional")
    end

    test "returns {:error, :not_found} for an unregistered name" do
      assert Registry.fetch("does_not_exist") == {:error, :not_found}
    end

    test "a client whose init_client/1 fails surfaces {:error, {:init_failed, reason}}" do
      assert Registry.fetch("test_client_failing_init") == {:error, {:init_failed, :boom}}
    end

    test "one broken client doesn't prevent other clients from registering" do
      assert {:ok, %{module: Maestro.TestClient}} = Registry.fetch("test_client")
      assert Registry.fetch("test_client_failing_init") == {:error, {:init_failed, :boom}}
    end

    test "init_client/1 runs exactly once per load!/0 call, not once per fetch/1 call" do
      assert {:ok, %{state: agent}} = Registry.fetch("test_client")
      assert {:ok, %{state: ^agent}} = Registry.fetch("test_client")
      assert {:ok, %{state: ^agent}} = Registry.fetch("test_client")
    end
  end

  describe "load!/0" do
    test "is safe to call more than once, rediscovering from scratch each time" do
      assert {:ok, %{state: first_agent}} = Registry.fetch("test_client")
      :ok = Registry.load!()
      assert {:ok, %{state: second_agent}} = Registry.fetch("test_client")
      refute first_agent == second_agent
    end
  end
end
