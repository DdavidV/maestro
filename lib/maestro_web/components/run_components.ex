defmodule MaestroWeb.RunComponents do
  @moduledoc """
  Shared rendering for `MaestroWeb.RunLive.Show`: the suite/testcase/step
  status tree and its `:pending`/`:running`/`:ok`/`:error` badge.
  """

  use Phoenix.Component

  @doc "A `:pending`/`:running`/`:ok`/`:error` status badge, daisyUI-colored."
  attr :status, :atom, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm", status_class(@status)]}>{@status}</span>
    """
  end

  defp status_class(:ok), do: "badge-success"
  defp status_class(:error), do: "badge-error"
  defp status_class(:running), do: "badge-info"
  defp status_class(:pending), do: "badge-ghost"

  @doc "One suite's card within a run: status badge, name, its testcases (once it has any)."
  attr :suite, :map, required: true

  def suite_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 p-4 mb-4">
      <div class="flex items-center gap-2 mb-2">
        <.status_badge status={@suite.status} />
        <span class="font-semibold font-mono">{@suite.id}</span>
      </div>

      <.testcase_row :for={testcase <- @suite.testcases} testcase={testcase} />
    </div>
    """
  end

  attr :testcase, :map, required: true

  defp testcase_row(assigns) do
    ~H"""
    <div class="ml-4 border-l-2 border-base-300 pl-4 py-1">
      <div class="flex items-center gap-2">
        <.status_badge status={@testcase.status} />
        <span class="font-mono text-sm">{@testcase.id}</span>
      </div>

      <div :for={step <- @testcase.steps} class="ml-4 flex items-center gap-2 text-sm">
        <.status_badge status={step.status} />
        <span class="text-base-content/70">{step.name}</span>
      </div>
    </div>
    """
  end
end
