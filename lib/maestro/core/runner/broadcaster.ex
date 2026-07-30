defmodule Maestro.Core.Runner.Broadcaster do
  @moduledoc """
  Thin `Phoenix.PubSub` wrapper broadcasting a run's progress as it
  happens, so a LiveView showing that run updates live instead of polling
  `Maestro.Core.Runner.status/1`/`result/1`.

  One topic per `run_id` alone.

  Message shapes broadcast, in the order they occur for one run:

    * `{:suite_started, suite_id}` a suite transitions to `:running`.
    * `{:testcase_result, suite_id, testcase_run_result}` one testcase
      within that suite finished (`t:Maestro.testcase_run_result/0`).
    * `{:suite_result, suite_run_result}` the suite itself finished
      (`t:Maestro.suite_run_result/0`, already containing every testcase).
    * `{:run_finalized, run_status}` the whole run reached a terminal
      status (`t:Maestro.run_status/0`, `:ok` or `:error`).
  """

  @pubsub Maestro.PubSub

  @spec topic(Maestro.run_id()) :: String.t()
  def topic(run_id), do: "maestro:run:#{run_id}"

  @doc "Subscribes the calling process to `run_id`'s progress messages."
  @spec subscribe(Maestro.run_id()) :: :ok | {:error, term()}
  def subscribe(run_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(run_id))
  end

  @doc false
  @spec broadcast(Maestro.run_id(), term()) :: :ok
  def broadcast(run_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic(run_id), message)
  end
end
