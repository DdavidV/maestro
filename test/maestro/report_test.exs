defmodule Maestro.ReportTest do
  use ExUnit.Case, async: false

  import Maestro.WorkspaceFixtures

  alias Maestro.Core.Runner
  alias Maestro.Report

  defmodule DummyLayout do
    @moduledoc false
    @behaviour Maestro.Report.Layout

    @impl true
    def render(_model), do: "dummy layout output"
  end

  setup do
    :ok = isolate_workspace_registry!()

    report_dir =
      Path.join(
        System.tmp_dir!(),
        "maestro_report_test_out_#{System.unique_integer([:positive])}"
      )

    previous_report_dir = Application.get_env(:maestro, :report_dir)
    Application.put_env(:maestro, :report_dir, report_dir)

    on_exit(fn ->
      File.rm_rf!(report_dir)

      if previous_report_dir do
        Application.put_env(:maestro, :report_dir, previous_report_dir)
      else
        Application.delete_env(:maestro, :report_dir)
      end
    end)

    %{workspace: workspace_fixture(), report_dir: report_dir}
  end

  defp inline_suite(id) do
    %{
      "id" => id,
      "testcases" => [
        %{
          "id" => "#{id}_tc1",
          "steps" => [
            %{
              "client" => "test_client_no_optional",
              "template" => %{"clients" => ["test_client_no_optional"], "payload" => %{"a" => 1}},
              "dataset" => %{"data" => %{"a" => 1}}
            }
          ]
        }
      ]
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

  describe "render/2" do
    test "returns {:error, :not_found} for an unknown run_id" do
      assert Report.render("does_not_exist") == {:error, :not_found}
    end

    test "returns {:ok, html} containing the run's suite ids on a completed run", %{
      workspace: workspace
    } do
      assert {:ok, run_id} = Runner.run(workspace, [inline_suite("checkout")])
      wait_until_done(run_id)

      assert {:ok, html} = Report.render(run_id)
      assert html =~ "checkout"
      assert html =~ run_id
    end

    test "an explicit layout argument overrides the configured default", %{workspace: workspace} do
      assert {:ok, run_id} = Runner.run(workspace, [inline_suite("checkout")])
      wait_until_done(run_id)

      assert Report.render(run_id, DummyLayout) == {:ok, "dummy layout output"}
    end
  end

  describe "generate/2" do
    test "returns {:error, :not_found} for an unknown run_id" do
      assert Report.generate("does_not_exist") == {:error, :not_found}
    end

    test "writes a file to report_path/1, creating report_dir if missing", %{
      report_dir: report_dir,
      workspace: workspace
    } do
      refute File.exists?(report_dir)

      assert {:ok, run_id} = Runner.run(workspace, [inline_suite("checkout")])
      wait_until_done(run_id)

      assert Report.generate(run_id) == :ok

      path = Report.report_path(run_id)
      assert File.exists?(path)
      assert File.read!(path) =~ "checkout"
    end

    test "an explicit layout argument is used for the written file", %{workspace: workspace} do
      assert {:ok, run_id} = Runner.run(workspace, [inline_suite("checkout")])
      wait_until_done(run_id)

      assert Report.generate(run_id, DummyLayout) == :ok
      assert File.read!(Report.report_path(run_id)) == "dummy layout output"
    end

    test "returns {:error, {:write_failed, _}} when report_dir can't be created", %{
      workspace: workspace
    } do
      assert {:ok, run_id} = Runner.run(workspace, [inline_suite("checkout")])
      wait_until_done(run_id)

      # Point report_dir at a path whose parent is a file, not a directory,
      # so File.mkdir_p/1 fails cleanly (portable across filesystems).
      blocking_file =
        Path.join(
          System.tmp_dir!(),
          "maestro_report_blocker_#{System.unique_integer([:positive])}"
        )

      File.write!(blocking_file, "not a directory")
      on_exit(fn -> File.rm(blocking_file) end)

      Application.put_env(:maestro, :report_dir, Path.join(blocking_file, "reports"))

      assert {:error, {:write_failed, _reason}} = Report.generate(run_id)
    end
  end
end
