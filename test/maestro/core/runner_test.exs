defmodule Maestro.Core.RunnerTest do
  use ExUnit.Case, async: false

  import Maestro.WorkspaceFixtures
  alias Maestro.Core.Runner
  alias Maestro.Core.Runner.Broadcaster

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  defp inline_suite(id, opts \\ []) do
    client = Keyword.get(opts, :client, "test_client_no_optional")
    assert_entries = Keyword.get(opts, :assert, [])

    step =
      %{
        "client" => client,
        "template" => %{"clients" => [client], "payload" => %{"marker" => id}},
        "dataset" => %{"data" => %{"marker" => id}}
      }
      |> Map.put("assert", assert_entries)
      |> Enum.reject(fn {_k, v} -> v == [] end)
      |> Map.new()

    %{
      "id" => id,
      "testcases" => [%{"id" => "#{id}_tc1", "steps" => [step]}]
    }
  end

  defp wait_until_done(run_id, tries \\ 50) do
    {:ok, progress} = Runner.status(run_id)

    if progress.status in [:ok, :error] or tries == 0 do
      progress
    else
      Process.sleep(20)
      wait_until_done(run_id, tries - 1)
    end
  end

  defp wait_until_first_suite_running(run_id, tries \\ 50) do
    {:ok, progress} = Runner.status(run_id)
    first_status = progress.suites |> List.first() |> Map.get(:status)

    if first_status != :pending or tries == 0 do
      progress
    else
      Process.sleep(5)
      wait_until_first_suite_running(run_id, tries - 1)
    end
  end

  describe "run/1: non-blocking execution" do
    test "returns immediately, doesn't block on a slow step", %{workspace: workspace} do
      suite = inline_suite("slow_suite", client: "test_client_slow")

      {elapsed_us, {:ok, run_id}} = :timer.tc(fn -> Runner.run(workspace, [suite]) end)

      assert elapsed_us < 100_000

      progress = wait_until_first_suite_running(run_id)
      assert %{status: :running, suites: [%{id: "slow_suite", status: :running}]} = progress

      wait_until_done(run_id)
    end
  end

  describe "broadcasting" do
    test "broadcasts suite/testcase/run-finalized messages, in order, for a multi-suite run", %{
      workspace: workspace
    } do
      suites = [inline_suite("suite_a"), inline_suite("suite_b")]

      {:ok, run_id} = Runner.run(workspace, suites)
      :ok = Broadcaster.subscribe(run_id)

      wait_until_done(run_id)

      assert_received {:suite_started, "suite_a"}
      assert_received {:testcase_result, "suite_a", %{id: "suite_a_tc1", status: :ok}}
      assert_received {:suite_result, %{id: "suite_a", status: :ok}}
      assert_received {:suite_started, "suite_b"}
      assert_received {:testcase_result, "suite_b", %{id: "suite_b_tc1", status: :ok}}
      assert_received {:suite_result, %{id: "suite_b", status: :ok}}
      assert_received {:run_finalized, :ok}
    end

    test "broadcasts :run_finalized with :error when a testcase fails", %{workspace: workspace} do
      suite =
        inline_suite("failing_suite",
          assert: [%{"matcher" => "json_match", "path" => "$.nope", "expected" => "x"}]
        )

      {:ok, run_id} = Runner.run(workspace, [suite])
      :ok = Broadcaster.subscribe(run_id)

      wait_until_done(run_id)

      assert_received {:run_finalized, :error}
    end
  end

  describe "run history" do
    test "list_for_workspace/1 lists this workspace's runs, newest first, without other workspaces' runs",
         %{workspace: workspace} do
      other_workspace = workspace_fixture()

      {:ok, run_id_1} = Runner.run(workspace, [inline_suite("first")])
      wait_until_done(run_id_1)
      {:ok, other_run_id} = Runner.run(other_workspace, [inline_suite("elsewhere")])
      wait_until_done(other_run_id)
      {:ok, run_id_2} = Runner.run(workspace, [inline_suite("second")])
      wait_until_done(run_id_2)

      summaries = Runner.list_for_workspace(workspace)

      assert Enum.map(summaries, & &1.run_id) == [run_id_2, run_id_1]
      assert Enum.all?(summaries, &(&1.status == :ok))
      assert Enum.all?(summaries, &(&1.suite_count == 1))
      assert Enum.all?(summaries, &match?(%DateTime{}, &1.started_at))
    end

    test "delete/1 removes a single run from history and from result/1", %{workspace: workspace} do
      {:ok, run_id} = Runner.run(workspace, [inline_suite("a")])
      wait_until_done(run_id)

      :ok = Runner.delete(run_id)

      assert Runner.list_for_workspace(workspace) == []
      assert Runner.result(run_id) == {:error, :not_found}
    end

    test "clear_history/1 removes every run for this workspace only", %{workspace: workspace} do
      other_workspace = workspace_fixture()

      {:ok, run_id} = Runner.run(workspace, [inline_suite("a")])
      wait_until_done(run_id)
      {:ok, other_run_id} = Runner.run(other_workspace, [inline_suite("b")])
      wait_until_done(other_run_id)

      :ok = Runner.clear_history(workspace)

      assert Runner.list_for_workspace(workspace) == []
      assert length(Runner.list_for_workspace(other_workspace)) == 1
    end
  end

  describe "status/1 transitions" do
    test "unknown run_id is :not_found" do
      assert Runner.status("does_not_exist") == {:error, :not_found}
    end

    test "reports per-suite progress: running suite, pending suites, then all done", %{
      workspace: workspace
    } do
      suites = [
        inline_suite("first", client: "test_client_slow"),
        inline_suite("second")
      ]

      {:ok, run_id} = Runner.run(workspace, suites)

      progress = wait_until_first_suite_running(run_id)

      assert %{
               status: :running,
               suites: [
                 %{id: "first", status: :running},
                 %{id: "second", status: :pending}
               ]
             } = progress

      final = wait_until_done(run_id)

      assert final.status == :ok
      assert Enum.map(final.suites, & &1.status) == [:ok, :ok]
    end

    test "a suite with a failing assertion ends that suite (and the run) at :error", %{
      workspace: workspace
    } do
      suite =
        inline_suite("failing",
          assert: [%{"expected" => %{"echo" => %{"payload" => %{"nope" => true}}}}]
        )

      {:ok, run_id} = Runner.run(workspace, [suite])
      final = wait_until_done(run_id)

      assert final.status == :error
      assert [%{status: :error}] = final.suites
    end
  end

  describe "result/1" do
    test "available and correct after completion", %{workspace: workspace} do
      suite = inline_suite("resultful")
      {:ok, run_id} = Runner.run(workspace, [suite])
      wait_until_done(run_id)

      assert {:ok, result} = Runner.result(run_id)
      assert result.run_id == run_id
      assert result.status == :ok

      assert [
               %{
                 id: "resultful",
                 status: :ok,
                 testcases: [
                   %{
                     id: "resultful_tc1",
                     status: :ok,
                     steps: [%{status: :ok, client: "test_client_no_optional"}]
                   }
                 ]
               }
             ] = result.suites
    end
  end

  describe "result/2 and result/3: scoped lookup" do
    test "result/2 finds a suite by id, without the other suites in the run", %{
      workspace: workspace
    } do
      suites = [inline_suite("find_a"), inline_suite("find_b")]
      {:ok, run_id} = Runner.run(workspace, suites)
      wait_until_done(run_id)

      assert {:ok, %{id: "find_b", testcases: [%{id: "find_b_tc1"}]}} =
               Runner.result(run_id, "find_b")
    end

    test "result/2 with an unknown suite id is :not_found", %{workspace: workspace} do
      {:ok, run_id} = Runner.run(workspace, [inline_suite("only_suite")])
      wait_until_done(run_id)

      assert Runner.result(run_id, "does_not_exist") == {:error, :not_found}
    end

    test "result/2 with an unknown run_id is :not_found" do
      assert Runner.result("does_not_exist", "any_suite") == {:error, :not_found}
    end

    test "result/3 finds a testcase by id, scoped to its suite", %{workspace: workspace} do
      {:ok, run_id} = Runner.run(workspace, [inline_suite("scoped")])
      wait_until_done(run_id)

      assert {:ok, %{id: "scoped_tc1", steps: [%{status: :ok}]}} =
               Runner.result(run_id, "scoped", "scoped_tc1")
    end

    test "result/3 with a testcase id belonging to a different suite is :not_found (scoped, not global)",
         %{workspace: workspace} do
      suites = [inline_suite("owner_a"), inline_suite("owner_b")]
      {:ok, run_id} = Runner.run(workspace, suites)
      wait_until_done(run_id)

      assert Runner.result(run_id, "owner_a", "owner_b_tc1") == {:error, :not_found}
    end

    test "result/3 with an unknown testcase id within a real suite is :not_found", %{
      workspace: workspace
    } do
      {:ok, run_id} = Runner.run(workspace, [inline_suite("has_testcases")])
      wait_until_done(run_id)

      assert Runner.result(run_id, "has_testcases", "does_not_exist") ==
               {:error, :not_found}
    end

    test "a duplicate suite id across two entries in the same run resolves to the first match", %{
      workspace: workspace
    } do
      suite_v1 = inline_suite("dup_id")
      [testcase] = suite_v1["testcases"]
      suite_v2 = %{suite_v1 | "testcases" => [%{testcase | "id" => "second_copy_tc"}]}

      {:ok, run_id} = Runner.run(workspace, [suite_v1, suite_v2])
      wait_until_done(run_id)

      assert {:ok, %{testcases: [%{id: "dup_id_tc1"}]}} = Runner.result(run_id, "dup_id")
    end
  end

  describe "multiple suites in one run" do
    test "a file-path entry and an inline entry both execute, in order", %{workspace: workspace} do
      resource_fixture!(workspace, :suite, "file_suite", %{
        "id" => "from_file",
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

      inline = inline_suite("from_inline")

      {:ok, run_id} = Runner.run(workspace, ["file_suite", inline])
      final = wait_until_done(run_id)

      assert final.status == :ok
      assert Enum.map(final.suites, & &1.id) == ["from_file", "from_inline"]
      assert Enum.map(final.suites, & &1.status) == [:ok, :ok]
    end

    test "the first suite finishes before the second starts (sequential, not concurrent)", %{
      workspace: workspace
    } do
      suites = [
        inline_suite("seq_first", client: "test_client_slow"),
        inline_suite("seq_second")
      ]

      {:ok, run_id} = Runner.run(workspace, suites)

      progress = wait_until_first_suite_running(run_id)
      assert %{suites: [%{status: :running}, %{status: :pending}]} = progress

      wait_until_done(run_id)
    end
  end

  describe "resolution failure blocks the whole call" do
    test "one bad entry among valid ones prevents anything from running", %{workspace: workspace} do
      valid_a = inline_suite("valid_a")
      valid_b = inline_suite("valid_b")

      assert {:error, resolve_errors} =
               Runner.run(workspace, [valid_a, "nonexistent_suite_file", valid_b])

      assert [{1, _reason}] = resolve_errors

      # nothing should have run: no run_id was returned, so there is nothing
      # to poll, and TestClientNoOptional records no calls anywhere for us
      # to check directly, so the key assertion is simply the return shape
      # above (no {:ok, run_id} at all) plus no crash/side effect.
    end

    test "invalid entries (not a list) is rejected synchronously", %{workspace: workspace} do
      assert Runner.run(workspace, %{"not" => "a list"}) == {:error, :invalid_entries}
      assert Runner.run(workspace, "also not a list") == {:error, :invalid_entries}
    end
  end

  describe "empty entries" do
    test "completes immediately with no suites", %{workspace: workspace} do
      {:ok, run_id} = Runner.run(workspace, [])
      final = wait_until_done(run_id)

      assert final.status == :ok
      assert final.suites == []
    end
  end

  describe "concurrent runs don't interfere" do
    test "distinct run_ids, independently correct results", %{workspace: workspace} do
      {:ok, run_id_a} = Runner.run(workspace, [inline_suite("run_a_suite")])
      {:ok, run_id_b} = Runner.run(workspace, [inline_suite("run_b_suite")])

      assert run_id_a != run_id_b

      final_a = wait_until_done(run_id_a)
      final_b = wait_until_done(run_id_b)

      assert Enum.map(final_a.suites, & &1.id) == ["run_a_suite"]
      assert Enum.map(final_b.suites, & &1.id) == ["run_b_suite"]

      {:ok, result_a} = Runner.result(run_id_a)
      {:ok, result_b} = Runner.result(run_id_b)
      assert Enum.map(result_a.suites, & &1.id) == ["run_a_suite"]
      assert Enum.map(result_b.suites, & &1.id) == ["run_b_suite"]
    end
  end

  describe "fresh saved state per testcase" do
    test "a placeholder saved by one testcase does not leak into the next", %{
      workspace: workspace
    } do
      step1 = %{
        "client" => "test_client_no_optional",
        "template" => %{"clients" => ["test_client_no_optional"], "payload" => %{"v" => 1}},
        "dataset" => %{"data" => %{"marker" => "tc1"}},
        "save" => [%{"path" => "$.echo.payload.v", "as" => "leaked_value"}]
      }

      step2 = %{
        "client" => "test_client_no_optional",
        "template" => %{
          "clients" => ["test_client_no_optional"],
          "payload" => %{"got" => "{{leaked_value}}"}
        },
        "dataset" => %{"data" => %{"marker" => "tc2"}}
      }

      suite = %{
        "id" => "leak_check",
        "testcases" => [
          %{"id" => "tc1", "steps" => [step1]},
          %{"id" => "tc2", "steps" => [step2]}
        ]
      }

      {:ok, run_id} = Runner.run(workspace, [suite])
      final = wait_until_done(run_id)

      assert final.status == :error
      assert {:ok, result} = Runner.result(run_id)
      [%{testcases: [_tc1, tc2]}] = result.suites
      assert [%{status: :error}] = tc2.steps
    end
  end

  describe "run_test_plan/1" do
    test "runs every suite named in the test plan's test_suites, in order", %{
      workspace: workspace
    } do
      resource_fixture!(workspace, :suite, "plan_suite_a", inline_suite("plan_suite_a"))
      resource_fixture!(workspace, :suite, "plan_suite_b", inline_suite("plan_suite_b"))

      resource_fixture!(workspace, :test_plan, "nightly", %{
        "id" => "nightly",
        "test_suites" => ["plan_suite_a", "plan_suite_b"]
      })

      {:ok, run_id} = Runner.run_test_plan(workspace, "nightly")
      final = wait_until_done(run_id)

      assert final.status == :ok
      assert Enum.map(final.suites, & &1.id) == ["plan_suite_a", "plan_suite_b"]
    end

    test "an unknown test plan name is a synchronous error, no run started", %{
      workspace: workspace
    } do
      assert Runner.run_test_plan(workspace, "does_not_exist") ==
               {:error, {:test_plan_not_found, "does_not_exist"}}
    end

    test "a test plan that fails schema validation is a synchronous error", %{
      workspace: workspace
    } do
      raw_resource_fixture!(workspace, :test_plan, "broken", %{"id" => "broken"})

      assert Runner.run_test_plan(workspace, "broken") ==
               {:error, {:test_plan_not_found, "broken"}}
    end

    test "a test plan naming a suite that fails to resolve reports the same error run/1 would", %{
      workspace: workspace
    } do
      resource_fixture!(workspace, :suite, "plan_suite_ok", inline_suite("plan_suite_ok"))

      resource_fixture!(workspace, :test_plan, "partial", %{
        "id" => "partial",
        "test_suites" => ["plan_suite_ok", "nonexistent_suite_file"]
      })

      assert {:error, resolve_errors} = Runner.run_test_plan(workspace, "partial")
      assert [{1, _reason}] = resolve_errors
    end
  end

  describe "automatic report generation" do
    setup do
      report_dir =
        Path.join(
          System.tmp_dir!(),
          "maestro_runner_report_test_#{System.unique_integer([:positive])}"
        )

      previous = Application.get_env(:maestro, :report_dir)
      previous_layout = Application.get_env(:maestro, :report_layout)
      previous_auto = Application.get_env(:maestro, :auto_report)
      Application.put_env(:maestro, :report_dir, report_dir)

      on_exit(fn ->
        File.rm_rf!(report_dir)

        if previous do
          Application.put_env(:maestro, :report_dir, previous)
        else
          Application.delete_env(:maestro, :report_dir)
        end

        if previous_layout do
          Application.put_env(:maestro, :report_layout, previous_layout)
        else
          Application.delete_env(:maestro, :report_layout)
        end

        if previous_auto do
          Application.put_env(:maestro, :auto_report, previous_auto)
        else
          Application.delete_env(:maestro, :auto_report)
        end
      end)

      %{report_dir: report_dir}
    end

    defp report_path!(run_id) do
      {:ok, path} = Maestro.Report.report_path(run_id)
      path
    end

    test "a report is written automatically after a passing run", %{workspace: workspace} do
      {:ok, run_id} = Runner.run(workspace, [inline_suite("s1")])
      final = wait_until_done(run_id)

      assert final.status == :ok
      assert File.exists?(report_path!(run_id))
    end

    test "a report is written automatically after a run that ends :error", %{workspace: workspace} do
      failing_assert = [%{"matcher" => "test_matcher", "should_fail" => true, "expected" => nil}]
      {:ok, run_id} = Runner.run(workspace, [inline_suite("s1", assert: failing_assert)])
      final = wait_until_done(run_id)

      assert final.status == :error
      assert File.exists?(report_path!(run_id))
    end

    test "auto_report: false suppresses generation", %{workspace: workspace} do
      Application.put_env(:maestro, :auto_report, false)

      {:ok, run_id} = Runner.run(workspace, [inline_suite("s1")])
      wait_until_done(run_id)

      refute File.exists?(report_path!(run_id))
    end

    test "a crashing custom report_layout does not crash the run or corrupt run status", %{
      workspace: workspace
    } do
      Application.put_env(:maestro, :report_layout, Maestro.TestCrashingReportLayout)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:ok, run_id} = Runner.run(workspace, [inline_suite("s1")])
          final = wait_until_done(run_id)

          assert final.status == :ok
          assert {:ok, %{status: :ok}} = Runner.result(run_id)
          refute File.exists?(report_path!(run_id))
        end)

      assert log =~ "Maestro report generation crashed"
    end
  end
end
