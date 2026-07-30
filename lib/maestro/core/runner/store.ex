defmodule Maestro.Core.Runner.Store do
  @moduledoc """
  Owns the ETS tables backing `Maestro.Core.Runner`'s `run/1`/`status/1`/
  `result/1` state, plus per-workspace run history (`list_for_workspace/1`,
  `delete/1`, `clear_workspace/1`).

  One row per `run_id` in the main table (`{run_id, run_result}`), a
  second table mapping `run_id` to the `workspace_id` it was created
  under, and a third mapping `run_id` to its `started_at`
  (`DateTime.t()`), stamped once at `create/3` neither `workspace_id` nor
  `started_at` are part of `t:Maestro.run_result/0` itself (same reasoning
  as `workspace_id`'s own doc: they're bookkeeping metadata a caller with
  a `run_id` already in hand needs, not part of the run's own result
  shape). This `GenServer` is every table's owner and only writer
  (`create/3`, `mark_running/2`, `put_suite_result/3`, `finalize/1`,
  `delete/1`, `clear_workspace/1`) reads (`get/1`, `list_for_workspace/1`,
  `workspace_id/1`) go straight through `:ets.lookup/2` or `:ets.tab2list/1`,
  bypassing the server process entirely, since every table is `:protected`
  (readable by any process, writable only by the owner).

  No persistence across an application restart table contents are lost on
  restart, run history included this is a deliberate, documented scope
  limit (see the Web UI plan's Phase 4 "open questions"), not an oversight
  a durable run-history store is a separate, larger feature.
  """

  use GenServer

  @table :maestro_runs
  @workspace_table :maestro_runs_workspace
  @started_at_table :maestro_runs_started_at

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Creates a run's row: `status: :running`, one `:pending` placeholder per
  already-resolved suite, in the same order as `resolved_suites`. Stamps
  `started_at` (`DateTime.utc_now/0`) at creation time, used to order
  `list_for_workspace/1`'s results newest-first. `workspace_id` is stored
  on the row (not part of `t:Maestro.run_result/0` itself,
  `status/1`/`result/1` don't expose it) so a caller that already has a
  `run_id` (e.g. a LiveView showing `/workspace/:workspace_id/history/:run_id`)
  can confirm the run actually belongs to that workspace before displaying it.
  """
  @spec create(Maestro.run_id(), String.t(), [Maestro.suite()]) :: :ok
  def create(run_id, workspace_id, resolved_suites) do
    GenServer.call(__MODULE__, {:create, run_id, workspace_id, resolved_suites})
  end

  @doc "The `workspace_id` a run was created under, if the run exists."
  @spec workspace_id(Maestro.run_id()) :: {:ok, String.t()} | :error
  def workspace_id(run_id) do
    case :ets.lookup(@workspace_table, run_id) do
      [{^run_id, workspace_id}] -> {:ok, workspace_id}
      [] -> :error
    end
  end

  @doc """
  Every run created under `workspace_id`, newest-first (by `started_at`).
  Each entry is `{run_id, started_at, run_result}` a plain `Enum.map/2`
  away from whatever a `RunLive.Index`-style listing needs (id, status,
  suite count, started-at), without exposing `run_result`'s full
  suite/testcase/step tree unnecessarily for a list row.
  """
  @spec list_for_workspace(String.t()) :: [
          {Maestro.run_id(), DateTime.t(), Maestro.run_result()}
        ]
  def list_for_workspace(workspace_id) do
    @workspace_table
    |> :ets.tab2list()
    |> Enum.filter(fn {_run_id, wid} -> wid == workspace_id end)
    |> Enum.flat_map(fn {run_id, _wid} ->
      with {:ok, run_result} <- get(run_id),
           [{^run_id, started_at}] <- :ets.lookup(@started_at_table, run_id) do
        [{run_id, started_at, run_result}]
      else
        _ -> []
      end
    end)
    |> Enum.sort_by(fn {_run_id, started_at, _run_result} -> started_at end, {:desc, DateTime})
  end

  @doc "Removes one run from history (all of its state). Safe to call for an unknown `run_id`."
  @spec delete(Maestro.run_id()) :: :ok
  def delete(run_id) do
    GenServer.call(__MODULE__, {:delete, run_id})
  end

  @doc "Removes every run belonging to `workspace_id` from history."
  @spec clear_workspace(String.t()) :: :ok
  def clear_workspace(workspace_id) do
    GenServer.call(__MODULE__, {:clear_workspace, workspace_id})
  end

  @doc "Flips one suite's placeholder to `:running`."
  @spec mark_running(Maestro.run_id(), non_neg_integer) :: :ok
  def mark_running(run_id, index) do
    GenServer.call(__MODULE__, {:mark_running, run_id, index})
  end

  @doc "Overwrites one suite's slot with its final result."
  @spec put_suite_result(Maestro.run_id(), non_neg_integer, Maestro.suite_run_result()) :: :ok
  def put_suite_result(run_id, index, suite_run_result) do
    GenServer.call(__MODULE__, {:put_suite_result, run_id, index, suite_run_result})
  end

  @doc """
  Recomputes and sets the run's top-level `status`: `:ok` only if every
  suite is `:ok`, else `:error`.
  """
  @spec finalize(Maestro.run_id()) :: :ok
  def finalize(run_id) do
    GenServer.call(__MODULE__, {:finalize, run_id})
  end

  @doc "Force-marks a run `:error`, used when the executing Task itself crashes."
  @spec mark_crashed(Maestro.run_id()) :: :ok
  def mark_crashed(run_id) do
    GenServer.call(__MODULE__, {:mark_crashed, run_id})
  end

  @doc "Plain ETS read, bypasses the GenServer."
  @spec get(Maestro.run_id()) :: {:ok, Maestro.run_result()} | :error
  def get(run_id) do
    case :ets.lookup(@table, run_id) do
      [{^run_id, run_result}] -> {:ok, run_result}
      [] -> :error
    end
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])
    :ets.new(@workspace_table, [:set, :protected, :named_table, read_concurrency: true])
    :ets.new(@started_at_table, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:create, run_id, workspace_id, resolved_suites}, _from, state) do
    suites =
      Enum.map(resolved_suites, fn suite ->
        %{id: suite.id, status: :pending, testcases: []}
      end)

    :ets.insert(@workspace_table, {run_id, workspace_id})
    :ets.insert(@started_at_table, {run_id, DateTime.utc_now()})

    run_result = %{run_id: run_id, status: :running, suites: suites}
    :ets.insert(@table, {run_id, run_result})
    {:reply, :ok, state}
  end

  def handle_call({:delete, run_id}, _from, state) do
    :ets.delete(@table, run_id)
    :ets.delete(@workspace_table, run_id)
    :ets.delete(@started_at_table, run_id)
    {:reply, :ok, state}
  end

  def handle_call({:clear_workspace, workspace_id}, _from, state) do
    @workspace_table
    |> :ets.tab2list()
    |> Enum.each(fn
      {run_id, ^workspace_id} ->
        :ets.delete(@table, run_id)
        :ets.delete(@workspace_table, run_id)
        :ets.delete(@started_at_table, run_id)

      _other ->
        :ok
    end)

    {:reply, :ok, state}
  end

  def handle_call({:mark_running, run_id, index}, _from, state) do
    update_suite(run_id, index, &Map.put(&1, :status, :running))
    {:reply, :ok, state}
  end

  def handle_call({:put_suite_result, run_id, index, suite_run_result}, _from, state) do
    update_suite(run_id, index, fn _old -> suite_run_result end)
    {:reply, :ok, state}
  end

  def handle_call({:finalize, run_id}, _from, state) do
    with {:ok, run_result} <- get(run_id) do
      status = if Enum.all?(run_result.suites, &(&1.status == :ok)), do: :ok, else: :error
      :ets.insert(@table, {run_id, %{run_result | status: status}})
    end

    {:reply, :ok, state}
  end

  def handle_call({:mark_crashed, run_id}, _from, state) do
    with {:ok, run_result} <- get(run_id) do
      :ets.insert(@table, {run_id, %{run_result | status: :error}})
    end

    {:reply, :ok, state}
  end

  defp update_suite(run_id, index, fun) do
    with {:ok, run_result} <- get(run_id) do
      suites = List.update_at(run_result.suites, index, fun)
      :ets.insert(@table, {run_id, %{run_result | suites: suites}})
    end
  end
end
