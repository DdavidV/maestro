defmodule MaestroWeb.RunComponents do
  @moduledoc """
  Shared rendering for `MaestroWeb.RunLive.Show`: the suite/testcase/step
  status tree and its `:pending`/`:running`/`:ok`/`:error` badge.
  """

  use Phoenix.Component

  import MaestroWeb.CoreComponents, only: [icon: 1]

  @doc """
  A `:pending`/`:running`/`:ok`/`:error` status badge, daisyUI-colored.
  `badge-success` is reserved for `:ok`, so its presence on a page means
  something actually passed.
  """
  attr :status, :atom, required: true
  attr :class, :any, default: nil

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm badge-soft gap-1.5 font-semibold uppercase tracking-wide text-[0.625rem]",
      status_class(@status),
      @class
    ]}>
      <span
        :if={@status != :running}
        class="size-1.5 rounded-full bg-current"
        aria-hidden="true"
      />
      <span
        :if={@status == :running}
        class="size-1.5 rounded-full bg-current motion-safe:animate-pulse"
        aria-hidden="true"
      />{@status}
    </span>
    """
  end

  defp status_class(:ok), do: "badge-success"
  defp status_class(:error), do: "badge-error"
  defp status_class(:running), do: "badge-info"
  defp status_class(:pending), do: "badge-ghost"

  @doc "A compact status glyph for dense rows (testcases, steps)."
  attr :status, :atom, required: true
  attr :class, :any, default: "size-4"

  def status_icon(assigns) do
    ~H"""
    <span title={to_string(@status)} class="inline-flex shrink-0">
      <.icon :if={@status == :ok} name="hero-check-circle-mini" class={[@class, "text-success"]} />
      <.icon :if={@status == :error} name="hero-x-circle-mini" class={[@class, "text-error"]} />
      <.icon
        :if={@status == :running}
        name="hero-arrow-path-mini"
        class={[@class, "text-info motion-safe:animate-spin"]}
      />
      <.icon
        :if={@status == :pending}
        name="hero-ellipsis-horizontal-circle-mini"
        class={[@class, "text-base-content/30"]}
      />
    </span>
    """
  end

  @doc """
  A row of summary tiles for a run: suites passed/failed/in progress and
  testcase totals, computed from whatever has been reported so far.
  """
  attr :suites, :list, required: true

  def run_summary(assigns) do
    suites = assigns.suites
    testcases = Enum.flat_map(suites, & &1.testcases)

    assigns =
      assign(assigns,
        total: length(suites),
        passed: Enum.count(suites, &(&1.status == :ok)),
        failed: Enum.count(suites, &(&1.status == :error)),
        in_progress: Enum.count(suites, &(&1.status in [:pending, :running])),
        tc_passed: Enum.count(testcases, &(&1.status == :ok)),
        tc_total: length(testcases)
      )

    ~H"""
    <div class="grid grid-cols-2 gap-px overflow-hidden rounded-box border border-base-300 bg-base-300 sm:grid-cols-4">
      <.summary_tile label="Suites" value={@total} />
      <.summary_tile label="Passed" value={@passed} tone="text-success" />
      <.summary_tile label="Failed" value={@failed} tone={@failed > 0 && "text-error"} />
      <.summary_tile
        label="Testcases passed"
        value={"#{@tc_passed}/#{@tc_total}"}
        hint={@in_progress > 0 && "#{@in_progress} suite(s) still running"}
      />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :tone, :any, default: nil
  attr :hint, :any, default: nil

  defp summary_tile(assigns) do
    ~H"""
    <div class="bg-base-100 px-4 py-3.5">
      <div class="text-xs font-medium text-base-content/50">{@label}</div>
      <div class={["mt-1 text-2xl font-semibold tabular-nums tracking-tight", @tone]}>
        {@value}
      </div>
      <div :if={@hint} class="mt-0.5 text-xs text-info">{@hint}</div>
    </div>
    """
  end

  @doc "One suite's card within a run: status badge, name, its testcases (once it has any)."
  attr :suite, :map, required: true

  def suite_card(assigns) do
    ~H"""
    <section class="panel overflow-hidden">
      <div class="flex items-center gap-3 border-b border-base-300 px-4 py-3">
        <.icon name="hero-beaker" class="size-4 shrink-0 text-base-content/40" />
        <span class="min-w-0 flex-1 truncate font-mono text-sm font-medium">{@suite.id}</span>
        <span :if={@suite.testcases != []} class="text-xs tabular-nums text-base-content/50">
          {Enum.count(@suite.testcases, &(&1.status == :ok))}/{length(@suite.testcases)} testcases
        </span>
        <.status_badge status={@suite.status} />
      </div>

      <div class="divide-y divide-base-300">
        <.testcase_row :for={testcase <- @suite.testcases} testcase={testcase} />
      </div>

      <p
        :if={@suite.testcases == []}
        class="flex items-center gap-2 px-4 py-3 text-sm text-base-content/50"
      >
        <.status_icon status={@suite.status} /> Waiting for testcases to finish…
      </p>
    </section>
    """
  end

  attr :testcase, :map, required: true

  defp testcase_row(assigns) do
    ~H"""
    <div class="px-4 py-3">
      <div class="flex items-center gap-2">
        <.status_icon status={@testcase.status} />
        <span class="font-mono text-[0.8125rem] font-medium">{@testcase.id}</span>
      </div>

      <ol :if={@testcase.steps != []} class="mt-2 ml-2 space-y-1 border-l border-base-300 pl-4">
        <li :for={step <- @testcase.steps} class="flex items-center gap-2 text-sm">
          <.status_icon status={step.status} class="size-3.5" />
          <span class={[
            "truncate",
            if(step.status == :error, do: "text-error", else: "text-base-content/70")
          ]}>
            {step.name}
          </span>
        </li>
      </ol>
    </div>
    """
  end

  @doc "Formats a `DateTime` (or ISO-8601 string) as `2026-10-17 14:32 UTC`."
  @spec format_datetime(DateTime.t() | String.t() | nil) :: String.t()
  def format_datetime(nil), do: "—"

  def format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  def format_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> format_datetime(dt)
      {:error, _reason} -> value
    end
  end

  @doc "A short relative time (`just now`, `5 min ago`, `3 h ago`, `2 d ago`) for `dt`."
  @spec relative_time(DateTime.t() | String.t() | nil) :: String.t()
  def relative_time(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt)

    cond do
      seconds < 45 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60) |> max(1)} min ago"
      seconds < 86_400 -> "#{div(seconds, 3600)} h ago"
      true -> "#{div(seconds, 86_400)} d ago"
    end
  end

  def relative_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> relative_time(dt)
      {:error, _reason} -> value
    end
  end

  def relative_time(nil), do: "—"
end
