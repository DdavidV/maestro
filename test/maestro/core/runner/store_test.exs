defmodule Maestro.Core.Runner.StoreTest do
  use ExUnit.Case, async: false

  alias Maestro.Core.Runner.Store

  defp suite(id), do: %{id: id, testcases: []}

  describe "create/2 and get/1" do
    test "creates a row with one :pending placeholder per suite, in order" do
      run_id = "run_#{System.unique_integer([:positive])}"
      :ok = Store.create(run_id, "test-workspace", [suite("a"), suite("b")])

      assert Store.get(run_id) ==
               {:ok,
                %{
                  run_id: run_id,
                  status: :running,
                  suites: [
                    %{id: "a", status: :pending, testcases: []},
                    %{id: "b", status: :pending, testcases: []}
                  ]
                }}
    end

    test "get/1 on an unknown run_id returns :error" do
      assert Store.get("does_not_exist") == :error
    end
  end

  describe "mark_running/2" do
    test "flips only the targeted suite's status" do
      run_id = "run_#{System.unique_integer([:positive])}"
      :ok = Store.create(run_id, "test-workspace", [suite("a"), suite("b")])
      :ok = Store.mark_running(run_id, 0)

      {:ok, row} = Store.get(run_id)
      assert Enum.at(row.suites, 0).status == :running
      assert Enum.at(row.suites, 1).status == :pending
    end
  end

  describe "put_suite_result/3" do
    test "overwrites only the targeted index" do
      run_id = "run_#{System.unique_integer([:positive])}"
      :ok = Store.create(run_id, "test-workspace", [suite("a"), suite("b")])

      result = %{id: "a", status: :ok, testcases: [%{id: "tc", status: :ok, steps: []}]}
      :ok = Store.put_suite_result(run_id, 0, result)

      {:ok, row} = Store.get(run_id)
      assert Enum.at(row.suites, 0) == result
      assert Enum.at(row.suites, 1) == %{id: "b", status: :pending, testcases: []}
    end
  end

  describe "finalize/1" do
    test "sets top-level status to :ok only if every suite is :ok" do
      run_id = "run_#{System.unique_integer([:positive])}"
      :ok = Store.create(run_id, "test-workspace", [suite("a"), suite("b")])
      :ok = Store.put_suite_result(run_id, 0, %{id: "a", status: :ok, testcases: []})
      :ok = Store.put_suite_result(run_id, 1, %{id: "b", status: :ok, testcases: []})
      :ok = Store.finalize(run_id)

      assert {:ok, %{status: :ok}} = Store.get(run_id)
    end

    test "sets top-level status to :error if any suite is :error" do
      run_id = "run_#{System.unique_integer([:positive])}"
      :ok = Store.create(run_id, "test-workspace", [suite("a"), suite("b")])
      :ok = Store.put_suite_result(run_id, 0, %{id: "a", status: :ok, testcases: []})
      :ok = Store.put_suite_result(run_id, 1, %{id: "b", status: :error, testcases: []})
      :ok = Store.finalize(run_id)

      assert {:ok, %{status: :error}} = Store.get(run_id)
    end
  end

  describe "mark_crashed/1" do
    test "force-sets top-level status to :error" do
      run_id = "run_#{System.unique_integer([:positive])}"
      :ok = Store.create(run_id, "test-workspace", [suite("a")])
      :ok = Store.mark_crashed(run_id)

      assert {:ok, %{status: :error}} = Store.get(run_id)
    end
  end

  describe "list_for_workspace/1" do
    test "lists every run for the given workspace, newest first" do
      workspace_id = "workspace_#{System.unique_integer([:positive])}"
      run_id_1 = "run_#{System.unique_integer([:positive])}"
      :ok = Store.create(run_id_1, workspace_id, [suite("a")])
      Process.sleep(5)
      run_id_2 = "run_#{System.unique_integer([:positive])}"
      :ok = Store.create(run_id_2, workspace_id, [suite("b")])

      entries = Store.list_for_workspace(workspace_id)

      assert Enum.map(entries, fn {run_id, _started_at, _result} -> run_id end) == [
               run_id_2,
               run_id_1
             ]
    end

    test "excludes runs belonging to a different workspace" do
      workspace_id = "workspace_#{System.unique_integer([:positive])}"
      other_workspace_id = "workspace_#{System.unique_integer([:positive])}"
      run_id = "run_#{System.unique_integer([:positive])}"
      other_run_id = "run_#{System.unique_integer([:positive])}"

      :ok = Store.create(run_id, workspace_id, [suite("a")])
      :ok = Store.create(other_run_id, other_workspace_id, [suite("b")])

      run_ids = Store.list_for_workspace(workspace_id) |> Enum.map(&elem(&1, 0))
      assert run_ids == [run_id]
    end

    test "returns [] for a workspace with no runs" do
      assert Store.list_for_workspace("workspace_with_no_runs_at_all") == []
    end
  end

  describe "delete/1" do
    test "removes a run from get/1, workspace_id/1, and list_for_workspace/1" do
      workspace_id = "workspace_#{System.unique_integer([:positive])}"
      run_id = "run_#{System.unique_integer([:positive])}"
      :ok = Store.create(run_id, workspace_id, [suite("a")])

      :ok = Store.delete(run_id)

      assert Store.get(run_id) == :error
      assert Store.workspace_id(run_id) == :error
      assert Store.list_for_workspace(workspace_id) == []
    end

    test "is a no-op for an unknown run_id" do
      assert Store.delete("does_not_exist_either") == :ok
    end
  end

  describe "clear_workspace/1" do
    test "removes every run for the given workspace, leaves other workspaces alone" do
      workspace_id = "workspace_#{System.unique_integer([:positive])}"
      other_workspace_id = "workspace_#{System.unique_integer([:positive])}"
      run_id = "run_#{System.unique_integer([:positive])}"
      other_run_id = "run_#{System.unique_integer([:positive])}"

      :ok = Store.create(run_id, workspace_id, [suite("a")])
      :ok = Store.create(other_run_id, other_workspace_id, [suite("b")])

      :ok = Store.clear_workspace(workspace_id)

      assert Store.list_for_workspace(workspace_id) == []
      assert Store.get(run_id) == :error
      assert Store.get(other_run_id) != :error
    end
  end

  describe "concurrent writers" do
    test "concurrent create/2 calls for different run_ids don't clobber each other" do
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            run_id = "run_concurrent_#{i}"
            :ok = Store.create(run_id, "test-workspace", [suite("suite_#{i}")])

            :ok =
              Store.put_suite_result(run_id, 0, %{id: "suite_#{i}", status: :ok, testcases: []})

            :ok = Store.finalize(run_id)
            run_id
          end)
        end

      run_ids = Task.await_many(tasks)

      for {run_id, i} <- Enum.with_index(run_ids, 1) do
        assert {:ok, %{status: :ok, suites: [%{id: suite_id}]}} = Store.get(run_id)
        assert suite_id == "suite_#{i}"
      end
    end
  end
end
