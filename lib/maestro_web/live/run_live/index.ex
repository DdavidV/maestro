defmodule MaestroWeb.RunLive.Index do
  @moduledoc """
  Lists every run in this workspace's history, newest first:
  `/workspace/:workspace_id/history`.

  Live-updates while any listed run is still `:running`: subscribes to
  each such run's own `Maestro.Core.Runner.Broadcaster` topic on mount and
  re-reads the whole list from `Runner.list_for_workspace/1` on
  `:run_finalized`.
  """

  use MaestroWeb, :live_view

  import MaestroWeb.RunComponents, only: [status_badge: 1]

  alias Maestro.Core.Runner
  alias Maestro.Core.Runner.Broadcaster

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "History") |> assign_runs()}
  end

  defp assign_runs(socket) do
    runs = Runner.list_for_workspace(socket.assigns.workspace)

    if connected?(socket) do
      Enum.each(runs, fn run ->
        if run.status == :running, do: Broadcaster.subscribe(run.run_id)
      end)
    end

    assign(socket, :runs, runs)
  end

  @impl true
  def handle_info({:run_finalized, _status}, socket) do
    {:noreply, assign_runs(socket)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("delete", %{"run_id" => run_id}, socket) do
    :ok = Runner.delete(run_id)
    {:noreply, assign_runs(socket)}
  end

  def handle_event("clear-history", _params, socket) do
    :ok = Runner.clear_history(socket.assigns.workspace)
    {:noreply, assign_runs(socket)}
  end
end
