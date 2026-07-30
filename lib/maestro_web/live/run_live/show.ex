defmodule MaestroWeb.RunLive.Show do
  @moduledoc """
  Shows one run's live progress: `/workspace/:workspace_id/history/:run_id`.

  `mount/3` loads the run's current `Maestro.Core.Runner.result/1` for the
  initial render, then subscribes to
  `Maestro.Core.Runner.Broadcaster`'s topic for `run_id` once
  `connected?(socket)`.

  `handle_info/2` patches `@run_result` directly from each broadcast
  payload rather than re-fetching `Runner.result/1` on every message: the
  payload already carries the changed data, so patching in place avoids a
  full-tree re-fetch/re-render on every testcase completion in a long run.
  """

  use MaestroWeb, :live_view

  import MaestroWeb.RunComponents

  alias Maestro.Core.Runner
  alias Maestro.Core.Runner.Broadcaster

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
         |> assign(:page_title, "Run #{run_id}")
         |> assign(:run_id, run_id)
         |> assign(:run_result, run_result)}

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
    socket =
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

    {:noreply, socket}
  end

  def handle_info({:suite_result, suite_run_result}, socket) do
    {:noreply, update_suite(socket, suite_run_result.id, fn _old -> suite_run_result end)}
  end

  def handle_info({:run_finalized, run_status}, socket) do
    {:noreply, update(socket, :run_result, &%{&1 | status: run_status})}
  end

  defp update_suite(socket, suite_id, fun) do
    update(socket, :run_result, fn run_result ->
      index = Enum.find_index(run_result.suites, &(&1.id == suite_id))

      if index do
        %{run_result | suites: List.update_at(run_result.suites, index, fun)}
      else
        run_result
      end
    end)
  end
end
