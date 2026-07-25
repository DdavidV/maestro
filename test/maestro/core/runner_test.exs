defmodule Maestro.Core.RunnerTest do
  use ExUnit.Case, async: false

  import Maestro.TestUtils
  alias Maestro.Core.Runner

  setup do
    dir =
      Path.join(System.tmp_dir!(), "maestro_runner_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    previous = Application.get_env(:maestro, :resource_dir)
    Application.put_env(:maestro, :resource_dir, dir)

    on_exit(fn ->
      File.rm_rf!(dir)

      if previous do
        Application.put_env(:maestro, :resource_dir, previous)
      else
        Application.delete_env(:maestro, :resource_dir)
      end
    end)

    %{dir: dir}
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
    test "returns immediately, doesn't block on a slow step" do
      suite = inline_suite("slow_suite", client: "test_client_slow")

      {elapsed_us, {:ok, run_id}} = :timer.tc(fn -> Runner.run([suite]) end)

      assert elapsed_us < 100_000

      progress = wait_until_first_suite_running(run_id)
      assert %{status: :running, suites: [%{id: "slow_suite", status: :running}]} = progress

      wait_until_done(run_id)
    end
  end

  describe "status/1 transitions" do
    test "unknown run_id is :not_found" do
      assert Runner.status("does_not_exist") == {:error, :not_found}
    end

    test "reports per-suite progress: running suite, pending suites, then all done" do
      suites = [
        inline_suite("first", client: "test_client_slow"),
        inline_suite("second")
      ]

      {:ok, run_id} = Runner.run(suites)

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

    test "a suite with a failing assertion ends that suite (and the run) at :error" do
      suite =
        inline_suite("failing",
          assert: [%{"expected" => %{"echo" => %{"payload" => %{"nope" => true}}}}]
        )

      {:ok, run_id} = Runner.run([suite])
      final = wait_until_done(run_id)

      assert final.status == :error
      assert [%{status: :error}] = final.suites
    end
  end

  describe "result/1" do
    test "available and correct after completion" do
      suite = inline_suite("resultful")
      {:ok, run_id} = Runner.run([suite])
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
    test "result/2 finds a suite by id, without the other suites in the run" do
      suites = [inline_suite("find_a"), inline_suite("find_b")]
      {:ok, run_id} = Runner.run(suites)
      wait_until_done(run_id)

      assert {:ok, %{id: "find_b", testcases: [%{id: "find_b_tc1"}]}} =
               Runner.result(run_id, "find_b")
    end

    test "result/2 with an unknown suite id is :not_found" do
      {:ok, run_id} = Runner.run([inline_suite("only_suite")])
      wait_until_done(run_id)

      assert Runner.result(run_id, "does_not_exist") == {:error, :not_found}
    end

    test "result/2 with an unknown run_id is :not_found" do
      assert Runner.result("does_not_exist", "any_suite") == {:error, :not_found}
    end

    test "result/3 finds a testcase by id, scoped to its suite" do
      {:ok, run_id} = Runner.run([inline_suite("scoped")])
      wait_until_done(run_id)

      assert {:ok, %{id: "scoped_tc1", steps: [%{status: :ok}]}} =
               Runner.result(run_id, "scoped", "scoped_tc1")
    end

    test "result/3 with a testcase id belonging to a different suite is :not_found (scoped, not global)" do
      suites = [inline_suite("owner_a"), inline_suite("owner_b")]
      {:ok, run_id} = Runner.run(suites)
      wait_until_done(run_id)

      assert Runner.result(run_id, "owner_a", "owner_b_tc1") == {:error, :not_found}
    end

    test "result/3 with an unknown testcase id within a real suite is :not_found" do
      {:ok, run_id} = Runner.run([inline_suite("has_testcases")])
      wait_until_done(run_id)

      assert Runner.result(run_id, "has_testcases", "does_not_exist") ==
               {:error, :not_found}
    end

    test "a duplicate suite id across two entries in the same run resolves to the first match" do
      suite_v1 = inline_suite("dup_id")
      [testcase] = suite_v1["testcases"]
      suite_v2 = %{suite_v1 | "testcases" => [%{testcase | "id" => "second_copy_tc"}]}

      {:ok, run_id} = Runner.run([suite_v1, suite_v2])
      wait_until_done(run_id)

      assert {:ok, %{testcases: [%{id: "dup_id_tc1"}]}} = Runner.result(run_id, "dup_id")
    end
  end

  describe "multiple suites in one run" do
    test "a file-path entry and an inline entry both execute, in order" do
      write_resource!("suites", "file_suite", %{
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

      {:ok, run_id} = Runner.run(["file_suite", inline])
      final = wait_until_done(run_id)

      assert final.status == :ok
      assert Enum.map(final.suites, & &1.id) == ["from_file", "from_inline"]
      assert Enum.map(final.suites, & &1.status) == [:ok, :ok]
    end

    test "the first suite finishes before the second starts (sequential, not concurrent)" do
      suites = [
        inline_suite("seq_first", client: "test_client_slow"),
        inline_suite("seq_second")
      ]

      {:ok, run_id} = Runner.run(suites)

      progress = wait_until_first_suite_running(run_id)
      assert %{suites: [%{status: :running}, %{status: :pending}]} = progress

      wait_until_done(run_id)
    end
  end

  describe "resolution failure blocks the whole call" do
    test "one bad entry among valid ones prevents anything from running" do
      valid_a = inline_suite("valid_a")
      valid_b = inline_suite("valid_b")

      assert {:error, resolve_errors} = Runner.run([valid_a, "nonexistent_suite_file", valid_b])
      assert [{1, _reason}] = resolve_errors

      # nothing should have run: no run_id was returned, so there is nothing
      # to poll, and TestClientNoOptional records no calls anywhere for us
      # to check directly, so the key assertion is simply the return shape
      # above (no {:ok, run_id} at all) plus no crash/side effect.
    end

    test "invalid entries (not a list) is rejected synchronously" do
      assert Runner.run(%{"not" => "a list"}) == {:error, :invalid_entries}
      assert Runner.run("also not a list") == {:error, :invalid_entries}
    end
  end

  describe "empty entries" do
    test "completes immediately with no suites" do
      {:ok, run_id} = Runner.run([])
      final = wait_until_done(run_id)

      assert final.status == :ok
      assert final.suites == []
    end
  end

  describe "concurrent runs don't interfere" do
    test "distinct run_ids, independently correct results" do
      {:ok, run_id_a} = Runner.run([inline_suite("run_a_suite")])
      {:ok, run_id_b} = Runner.run([inline_suite("run_b_suite")])

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
    test "a placeholder saved by one testcase does not leak into the next" do
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

      {:ok, run_id} = Runner.run([suite])
      final = wait_until_done(run_id)

      assert final.status == :error
      assert {:ok, result} = Runner.result(run_id)
      [%{testcases: [_tc1, tc2]}] = result.suites
      assert [%{status: :error}] = tc2.steps
    end
  end
end
