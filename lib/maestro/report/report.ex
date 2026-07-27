defmodule Maestro.Report do
  @moduledoc """
  Renders and writes HTML reports for a run, identified by `run_id`.

  Fetches the run's current `t:Maestro.run_result/0` via
  `Maestro.Core.Runner.result/1`, builds a `Maestro.Report.Model.t()` from
  it, and hands that to the configured `Maestro.Report.Layout`
  (`Maestro.Report.Layout.configured/0`, default
  `Maestro.Report.DefaultLayout`, overridable via
  `config :maestro, :report_layout`).

  `render/2` returns the HTML as a string with no filesystem interaction,
  for a caller that wants the markup itself (embedding, streaming, a
  different write target). `generate/2` is `render/2` plus writing the
  result to `report_path(run_id)` under `report_dir/0`, creating that
  directory first if needed the function `Maestro.Core.Runner` calls
  automatically after every run finishes (see `config :maestro,
  :auto_report`, on by default), and the one a caller invokes manually to
  regenerate a report (e.g. with a different layout, after disabling
  auto-generation, or for a still-`:running` run to inspect partial
  results).

  Both accept a `layout` override (second argument) so a one-off manual
  call doesn't require flipping the global `report_layout` config just to
  try a different layout module.
  """

  alias Maestro.Core.Runner
  alias Maestro.Report.Layout
  alias Maestro.Report.Model

  @doc """
  The directory reports are written under. Reads
  `config :maestro, :report_dir`, falling back to `priv/reports` under
  Maestro's own `priv_dir` if unset same convention as
  `Maestro.Resources.resource_dir/0`.
  """
  @spec report_dir() :: String.t()
  def report_dir do
    Application.get_env(:maestro, :report_dir) || Path.join(:code.priv_dir(:maestro), "reports")
  end

  @doc "The file a `generate/2` call for `run_id` writes (or overwrites)."
  @spec report_path(Maestro.run_id()) :: String.t()
  def report_path(run_id), do: Path.join(report_dir(), "maestro_report_#{run_id}.html")

  @doc """
  Renders `run_id`'s current result as a self-contained HTML string, via
  `layout` (default: `Maestro.Report.Layout.configured/0`).

  Returns `{:error, :not_found}` if `run_id` doesn't resolve (unknown, or
  never existed) same `:not_found` convention `Maestro.result/1` uses. A
  raise from `layout.render/1` itself (a broken custom layout module)
  propagates uncaught here deliberately: a direct, manual `render/2` call
  is exactly where a caller *wants* to see that failure immediately,
  unlike the automatic post-run hook (see `Maestro.Core.Runner`), which
  swallows it so a bad layout can't crash a run.
  """
  @spec render(Maestro.run_id(), module) :: {:ok, String.t()} | {:error, :not_found}
  def render(run_id, layout \\ Layout.configured()) do
    with {:ok, run_result} <- Runner.result(run_id) do
      {:ok, layout.render(Model.build(run_result))}
    end
  end

  @doc """
  `render/2` plus writing the result to `report_path(run_id)`, creating
  `report_dir/0` first if it doesn't exist yet. Overwrites any existing
  report file for the same `run_id`.

  Returns `{:error, :not_found}` for an unknown `run_id` (same as
  `render/2`), or `{:error, {:write_failed, reason}}` if the write itself
  fails (e.g. disk full, permission denied) `reason` is whatever
  `File.write/2`/`File.mkdir_p/1` returned. Never raises for these
  ordinary failure modes deliberately, since `Maestro.Core.Runner` calls
  this automatically after every run and must not let a report-write
  failure affect that run's already-finalized status. A raise from
  `layout.render/1` itself is not caught here, same as `render/2` (see
  its doc); `Maestro.Core.Runner`'s automatic hook adds its own outer
  `rescue` specifically to guard against that case, since swallowing an
  arbitrary raise is a policy decision for the automatic hook, not for
  this function's general contract.
  """
  @spec generate(Maestro.run_id(), module) ::
          :ok | {:error, :not_found | {:write_failed, term}}
  def generate(run_id, layout \\ Layout.configured()) do
    with {:ok, html} <- render(run_id, layout),
         :ok <- File.mkdir_p(report_dir()),
         :ok <- File.write(report_path(run_id), html) do
      :ok
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, {:write_failed, reason}}
    end
  end
end
