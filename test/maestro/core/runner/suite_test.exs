defmodule Maestro.Core.Runner.SuiteTest do
  use ExUnit.Case, async: false

  alias Maestro.Client.Registry, as: ClientRegistry
  alias Maestro.Core.Runner.Broadcaster
  alias Maestro.Core.Runner.Suite

  setup do
    :ok = ClientRegistry.load!()
    :ok
  end

  defp step(payload, data) do
    %{
      client: "test_client_no_optional",
      template: %{payload: payload, options: %{}},
      dataset: %{data: data},
      save: [],
      assert: []
    }
  end

  test "runs every testcase in order and reports :ok when all succeed" do
    suite = %{
      id: "suite1",
      testcases: [
        %{id: "tc1", steps: [step(%{"a" => 1}, %{"a" => 1})]},
        %{id: "tc2", steps: [step(%{"b" => 2}, %{"b" => 2})]}
      ]
    }

    assert %{
             id: "suite1",
             status: :ok,
             testcases: [%{id: "tc1", status: :ok}, %{id: "tc2", status: :ok}]
           } = Suite.run("test-run", suite)
  end

  test "reports :error if any testcase fails, still returns every testcase's result" do
    suite = %{
      id: "suite2",
      testcases: [
        %{id: "tc1", steps: [step(%{"a" => 1}, %{"a" => 1})]},
        %{id: "tc2", steps: [step(%{"missing" => "{{nope}}"}, %{})]}
      ]
    }

    assert %{
             id: "suite2",
             status: :error,
             testcases: [%{id: "tc1", status: :ok}, %{id: "tc2", status: :error}]
           } = Suite.run("test-run", suite)
  end

  test "an empty testcases list is trivially :ok" do
    assert Suite.run("test-run", %{id: "empty", testcases: []}) ==
             %{id: "empty", status: :ok, testcases: []}
  end

  test "broadcasts a :testcase_result message after each testcase finishes" do
    run_id = "run-broadcast-test"
    :ok = Broadcaster.subscribe(run_id)

    suite = %{
      id: "suite1",
      testcases: [
        %{id: "tc1", steps: [step(%{"a" => 1}, %{"a" => 1})]},
        %{id: "tc2", steps: [step(%{"b" => 2}, %{"b" => 2})]}
      ]
    }

    Suite.run(run_id, suite)

    assert_receive {:testcase_result, "suite1", %{id: "tc1", status: :ok}}
    assert_receive {:testcase_result, "suite1", %{id: "tc2", status: :ok}}
  end
end
