defmodule Maestro.Core.Runner.Store do
  @moduledoc """
  Owns the ETS table backing `Maestro.Core.Runner`'s `run/1`/`status/1`/
  `result/1` state.

  One row per `run_id`, `{run_id, run_result}`. This `GenServer` is the
  table's owner and only writer (`create/2`, `mark_running/2`,
  `put_suite_result/3`, `finalize/1`) reads (`get/1`) go straight through
  `:ets.lookup/2`, bypassing the server process entirely, since the table is
  `:protected` (readable by any process, writable only by the owner) — this
  keeps `status/1`/`result/1` polling cheap and non-blocking even while a
  write to a different run_id is in flight.

  No persistence across an application restart table contents are lost on
  restart.
  """

  use GenServer

  @table :maestro_runs

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Creates a run's row: `status: :running`, one `:pending` placeholder per
  already-resolved suite, in the same order as `resolved_suites`.
  """
  @spec create(Maestro.run_id(), [Maestro.suite()]) :: :ok
  def create(run_id, resolved_suites) do
    GenServer.call(__MODULE__, {:create, run_id, resolved_suites})
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
    {:ok, %{}}
  end

  @impl true
  def handle_call({:create, run_id, resolved_suites}, _from, state) do
    suites =
      Enum.map(resolved_suites, fn suite ->
        %{id: suite.id, status: :pending, testcases: []}
      end)

    run_result = %{run_id: run_id, status: :running, suites: suites}
    :ets.insert(@table, {run_id, run_result})
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
