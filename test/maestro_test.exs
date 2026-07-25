defmodule MaestroTest do
  use ExUnit.Case, async: false

  describe "run/1, status/1, result/1 delegate to Maestro.Core.Runner" do
    test "a valid inline suite runs end-to-end through the public API" do
      suite = %{
        "id" => "smoke_suite",
        "testcases" => [
          %{
            "id" => "tc1",
            "steps" => [
              %{
                "client" => "test_client_no_optional",
                "template" => %{
                  "clients" => ["test_client_no_optional"],
                  "payload" => %{"a" => 1}
                },
                "dataset" => %{"data" => %{"a" => 1}}
              }
            ]
          }
        ]
      }

      assert {:ok, run_id} = Maestro.run([suite])
      assert is_binary(run_id)

      final = wait_until_done(run_id)
      assert final.status == :ok

      assert {:ok, %{status: :ok, suites: [%{id: "smoke_suite"}]}} = Maestro.result(run_id)

      assert {:ok, %{id: "smoke_suite"}} = Maestro.result(run_id, "smoke_suite")
      assert {:ok, %{id: "tc1"}} = Maestro.result(run_id, "smoke_suite", "tc1")
    end

    test "invalid entries surfaces the same error as Runner" do
      assert Maestro.run(%{"not" => "a list"}) == {:error, :invalid_entries}
    end

    test "status/1 and result/1,2,3 report :not_found for an unknown run_id" do
      assert Maestro.status("does_not_exist") == {:error, :not_found}
      assert Maestro.result("does_not_exist") == {:error, :not_found}
      assert Maestro.result("does_not_exist", "any") == {:error, :not_found}
      assert Maestro.result("does_not_exist", "any", "any") == {:error, :not_found}
    end
  end

  defp wait_until_done(run_id, tries \\ 50) do
    {:ok, progress} = Maestro.status(run_id)

    if progress.status in [:ok, :error] or tries == 0 do
      progress
    else
      Process.sleep(20)
      wait_until_done(run_id, tries - 1)
    end
  end
end
