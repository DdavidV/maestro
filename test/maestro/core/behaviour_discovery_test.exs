defmodule Maestro.Core.BehaviourDiscoveryTest do
  use ExUnit.Case, async: true

  alias Maestro.Core.BehaviourDiscovery

  describe "modules_implementing/1" do
    test "finds every loaded module declaring the given behaviour" do
      modules = BehaviourDiscovery.modules_implementing(Maestro.Client)

      assert Maestro.TestClient in modules
    end

    test "finds implementations of a different behaviour independently" do
      modules = BehaviourDiscovery.modules_implementing(Maestro.Assert.Matcher)

      assert Maestro.TestMatcher in modules
      refute Maestro.TestClient in modules
    end

    test "a behaviour nothing implements returns an empty list" do
      assert BehaviourDiscovery.modules_implementing(GenStateMachine) == []
    end
  end
end
