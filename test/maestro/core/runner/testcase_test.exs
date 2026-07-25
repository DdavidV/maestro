defmodule Maestro.Core.Runner.TestcaseTest do
  use ExUnit.Case, async: false

  alias Maestro.Client.Registry, as: ClientRegistry
  alias Maestro.Core.Runner.Testcase

  setup do
    :ok = ClientRegistry.load!()
    :ok
  end

  defp step(opts) do
    %{
      client: Keyword.get(opts, :client, "test_client_no_optional"),
      template: %{payload: Keyword.fetch!(opts, :payload), options: %{}},
      dataset: Keyword.fetch!(opts, :dataset),
      save: Keyword.get(opts, :save, []),
      assert: Keyword.get(opts, :assert, [])
    }
  end

  test "runs a testcase's steps and reports :ok when every step succeeds" do
    testcase = %{
      id: "tc1",
      steps: [step(payload: %{"foo" => "{{foo}}"}, dataset: %{data: %{"foo" => "bar"}})]
    }

    assert %{id: "tc1", status: :ok, steps: [%{status: :ok}]} = Testcase.run(testcase)
  end

  test "reports :error if any step fails, still returns every step's result" do
    testcase = %{
      id: "tc2",
      steps: [
        step(payload: %{}, dataset: %{data: %{}}),
        step(payload: %{"missing" => "{{does_not_exist}}"}, dataset: %{data: %{}})
      ]
    }

    assert %{id: "tc2", status: :error, steps: [%{status: :ok}, %{status: :error}]} =
             Testcase.run(testcase)
  end

  test "each call starts with fresh saved state, not shared across testcases" do
    testcase = %{
      id: "tc3",
      steps: [step(payload: %{"got" => "{{leaked}}"}, dataset: %{data: %{}})]
    }

    assert %{status: :error} = Testcase.run(testcase)
  end
end
