defmodule Maestro.TestCrashingReportLayout do
  @moduledoc false
  @behaviour Maestro.Report.Layout

  @impl true
  def render(_model), do: raise("report layout boom")
end
