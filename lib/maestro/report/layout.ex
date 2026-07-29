defmodule Maestro.Report.Layout do
  @moduledoc """
  Behaviour for rendering a `Maestro.Report.Model.t()` into a self-contained
  HTML document (a `file://`-openable string, inline CSS, no external asset
  dependency).

  `Maestro.Report.DefaultLayout` is the built-in implementation. A host
  application can supply its own module implementing this single callback
  and point `config :maestro, :report_layout` at it instead a
  compiled-module reference instead of a filesystem path, since a report
  layout is HEEx/Elixir code, not a runtime-loaded resource (unlike
  suites/scenarios/datasets/templates, deliberately not modeled as a
  "resource kind").

  Not named "template" to avoid confusion with Maestro's existing,
  unrelated `t:Maestro.resolved_template/0` concept (an HTTP request
  payload/options template, nothing to do with report rendering).
  """

  @callback render(Maestro.Report.Model.t()) :: String.t()

  @doc """
  The configured layout module. Reads `config :maestro, :report_layout`,
  falling back to `Maestro.Report.DefaultLayout` if unset.
  """
  @spec configured() :: module
  def configured do
    Application.get_env(:maestro, :report_layout) || Maestro.Report.DefaultLayout
  end
end
