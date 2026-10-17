defmodule Maestro.Report.Format do
  @moduledoc """
  Behaviour for one output format a run's report can be rendered to (HTML,
  JUnit XML, or a host's own), and the list of formats Maestro writes after
  every run.

  A format turns a `Maestro.Report.Model.t()` into a string with `render/1`,
  the only required callback. The optional callbacks describe the output so
  `Maestro.Report` knows where to write it and how to serve it:

    * `name/0` the identifier used to pick this format over REST/the GUI
      (`?format=junit`). Defaults to `extension/0`.
    * `extension/0` the file extension written to disk
      (`maestro_report_<run_id>.<extension>`). Defaults to `"html"`.
    * `content_type/0` the MIME type served on download. Defaults to
      `"text/html"`.

  So a custom HTML report only needs `render/1`:

      defmodule MyApp.Maestro.ReportLayout do
        @behaviour Maestro.Report.Format

        @impl true
        def render(model), do: "<html>...</html>"
      end

  `Maestro.Report.DefaultLayout` (HTML) and `Maestro.Report.JUnit` (JUnit
  XML) are the built-in formats.

  ## Configuring which formats are written

      config :maestro, :report_formats, [
        Maestro.Report.DefaultLayout,
        Maestro.Report.JUnit
      ]

  `Maestro.Report.generate_all/1` (what runs automatically after every run,
  unless `:auto_report` is `false`) writes every format in this list, each to
  its own file, so each format's `extension/0` must be unique within it. If
  unset, it defaults to `[Maestro.Report.DefaultLayout]`.

  The **first** format in the list is the default one: what's rendered when
  no format is asked for (`Maestro.render_report/1`, `GET
  /api/runs/{run_id}/report` without `?format=`, the GUI's report download).
  """

  alias Maestro.Report.Model

  @callback render(Model.t()) :: String.t()
  @callback name() :: String.t()
  @callback extension() :: String.t()
  @callback content_type() :: String.t()

  @optional_callbacks name: 0, extension: 0, content_type: 0

  @builtin [Maestro.Report.DefaultLayout, Maestro.Report.JUnit]

  @doc """
  The formats written after every run: `config :maestro, :report_formats`,
  or `[Maestro.Report.DefaultLayout]` if unset.
  """
  @spec configured() :: [module]
  def configured do
    Application.get_env(:maestro, :report_formats, [Maestro.Report.DefaultLayout])
  end

  @doc """
  The default format, used whenever none is asked for explicitly: the first
  `configured/0` format, or `Maestro.Report.DefaultLayout` if that list is
  empty.
  """
  @spec default() :: module
  def default, do: List.first(configured()) || Maestro.Report.DefaultLayout

  @doc """
  Every format that can be requested by name: the configured ones first,
  then Maestro's built-in ones (`Maestro.Report.DefaultLayout`,
  `Maestro.Report.JUnit`), so a built-in format can always be downloaded
  on demand even when it isn't written automatically. When two formats
  share a name, the earlier one wins, so a configured custom HTML format
  shadows the built-in one.
  """
  @spec available() :: [module]
  def available do
    (configured() ++ @builtin)
    |> Enum.uniq()
    |> Enum.uniq_by(&name/1)
  end

  @doc "Looks up an `available/0` format by its `name/0`."
  @spec find(String.t()) :: {:ok, module} | {:error, :unknown_format}
  def find(name) when is_binary(name) do
    case Enum.find(available(), &(name(&1) == name)) do
      nil -> {:error, :unknown_format}
      format -> {:ok, format}
    end
  end

  @doc "`format`'s `name/0`, or its `extension/0` if it doesn't define one."
  @spec name(module) :: String.t()
  def name(format), do: optional(format, :name, fn -> extension(format) end)

  @doc "`format`'s `extension/0`, or `\"html\"` if it doesn't define one."
  @spec extension(module) :: String.t()
  def extension(format), do: optional(format, :extension, fn -> "html" end)

  @doc "`format`'s `content_type/0`, or `\"text/html\"` if it doesn't define one."
  @spec content_type(module) :: String.t()
  def content_type(format), do: optional(format, :content_type, fn -> "text/html" end)

  defp optional(format, callback, default) do
    if Code.ensure_loaded?(format) and function_exported?(format, callback, 0) do
      apply(format, callback, [])
    else
      default.()
    end
  end
end
