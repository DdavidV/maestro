defmodule MaestroTest do
  use ExUnit.Case, async: false

  import Maestro.WorkspaceFixtures

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  describe "run/2, status/1, result/1 delegate to Maestro.Core.Runner" do
    test "a valid inline suite runs end-to-end through the public API", %{workspace: workspace} do
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

      assert {:ok, run_id} = Maestro.run(workspace, [suite])
      assert is_binary(run_id)

      final = wait_until_done(run_id)
      assert final.status == :ok

      assert {:ok, %{status: :ok, suites: [%{id: "smoke_suite"}]}} = Maestro.result(run_id)

      assert {:ok, %{id: "smoke_suite"}} = Maestro.result(run_id, "smoke_suite")
      assert {:ok, %{id: "tc1"}} = Maestro.result(run_id, "smoke_suite", "tc1")
    end

    test "invalid entries surfaces the same error as Runner", %{workspace: workspace} do
      assert Maestro.run(workspace, %{"not" => "a list"}) == {:error, :invalid_entries}
    end

    test "status/1 and result/1,2,3 report :not_found for an unknown run_id" do
      assert Maestro.status("does_not_exist") == {:error, :not_found}
      assert Maestro.result("does_not_exist") == {:error, :not_found}
      assert Maestro.result("does_not_exist", "any") == {:error, :not_found}
      assert Maestro.result("does_not_exist", "any", "any") == {:error, :not_found}
    end
  end

  describe "run_test_plan/2 delegates to Maestro.Core.Runner" do
    test "runs the named test plan's suites end-to-end through the public API", %{
      workspace: workspace
    } do
      resource_fixture!(workspace, :suite, "plan_suite", %{
        "id" => "plan_suite",
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
      })

      resource_fixture!(workspace, :test_plan, "nightly", %{
        "id" => "nightly",
        "test_suites" => ["plan_suite"]
      })

      assert {:ok, run_id} = Maestro.run_test_plan(workspace, "nightly")
      final = wait_until_done(run_id)

      assert final.status == :ok
      assert {:ok, %{suites: [%{id: "plan_suite"}]}} = Maestro.result(run_id)
    end

    test "an unknown test plan name surfaces the same error as Runner", %{workspace: workspace} do
      assert Maestro.run_test_plan(workspace, "does_not_exist") ==
               {:error, {:test_plan_not_found, "does_not_exist"}}
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
