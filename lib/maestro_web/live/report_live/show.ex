defmodule MaestroWeb.ReportLive.Show do
  @moduledoc """
  Shows a run's report inline: `/workspace/:workspace_id/reports/:run_id`.

  Builds `Maestro.Report.Model.build/1` from the run's current
  `Maestro.Core.Runner.result/1` and renders it with
  `MaestroWeb.ReportComponents`.
  """

  use MaestroWeb, :live_view

  import MaestroWeb.ReportComponents

  alias Maestro.Core.Runner
  alias Maestro.Core.Runner.Broadcaster
  alias Maestro.Report.Model

  @impl true
  def mount(%{"run_id" => run_id}, _session, socket) do
    workspace = socket.assigns.workspace

    case Runner.workspace_id(run_id) do
      {:ok, workspace_id} when workspace_id == workspace.id ->
        {:ok, run_result} = Runner.result(run_id)

        if connected?(socket) do
          :ok = Broadcaster.subscribe(run_id)
        end

        {:ok,
         socket
         |> assign(:page_title, "Report for #{run_id}")
         |> assign(:run_id, run_id)
         |> assign(:run_result, run_result)
         |> assign(:model, Model.build(run_result))}

      {:ok, _other_workspace_id} ->
        {:ok,
         socket
         |> put_flash(:error, "Run #{run_id} does not belong to this workspace.")
         |> push_navigate(to: "/workspace/#{workspace.id}")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Run #{run_id} not found.")
         |> push_navigate(to: "/workspace/#{workspace.id}")}
    end
  end

  @impl true
  def handle_info({:suite_started, suite_id}, socket) do
    {:noreply, update_suite(socket, suite_id, &Map.put(&1, :status, :running))}
  end

  def handle_info({:testcase_result, suite_id, testcase_run_result}, socket) do
    update_suite(socket, suite_id, fn suite ->
      existing_index = Enum.find_index(suite.testcases, &(&1.id == testcase_run_result.id))

      testcases =
        if existing_index do
          List.replace_at(suite.testcases, existing_index, testcase_run_result)
        else
          suite.testcases ++ [testcase_run_result]
        end

      %{suite | testcases: testcases}
    end)
    |> then(&{:noreply, &1})
  end

  def handle_info({:suite_result, suite_run_result}, socket) do
    {:noreply, update_suite(socket, suite_run_result.id, fn _old -> suite_run_result end)}
  end

  def handle_info({:run_finalized, run_status}, socket) do
    {:noreply, update_run_result(socket, &%{&1 | status: run_status})}
  end

  defp update_suite(socket, suite_id, fun) do
    update_run_result(socket, fn run_result ->
      index = Enum.find_index(run_result.suites, &(&1.id == suite_id))

      if index do
        %{run_result | suites: List.update_at(run_result.suites, index, fun)}
      else
        run_result
      end
    end)
  end

  defp update_run_result(socket, fun) do
    run_result = fun.(socket.assigns.run_result)

    socket
    |> assign(:run_result, run_result)
    |> assign(:model, Model.build(run_result))
  end
end
