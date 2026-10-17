defmodule MaestroWeb.ReportController do
  @moduledoc """
  Downloads a run's report as a standalone file in the
  `Maestro.Report.Format.available/0` format named by the required
  `?format=` (e.g. `html`, `junit`).

  Calls `Maestro.render_report/2` directly, so the download always
  reflects the run's current state including a still-running run
  rather than whatever was last auto-generated to disk after the run finished.
  """

  use MaestroWeb, :controller

  alias Maestro.Core.Runner
  alias Maestro.Report.Format

  def download(conn, %{"workspace_id" => workspace_id, "run_id" => run_id} = params) do
    with {:ok, ^workspace_id} <- Runner.workspace_id(run_id),
         {:ok, format} <- requested_format(params),
         {:ok, body} <- Maestro.render_report(run_id, format) do
      conn
      |> put_resp_content_type(Format.content_type(format))
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="maestro_report_#{run_id}.#{Format.extension(format)}")
      )
      |> send_resp(200, body)
    else
      {:error, reason} when reason in [:unknown_format, :missing_format] ->
        conn
        |> put_flash(:error, format_error(params))
        |> redirect(to: ~p"/workspace/#{workspace_id}/reports/#{run_id}")

      _not_found_or_wrong_workspace ->
        conn
        |> put_flash(:error, "Run #{run_id} not found.")
        |> redirect(to: ~p"/workspace/#{workspace_id}")
    end
  end

  defp requested_format(%{"format" => name}) when is_binary(name), do: Format.find(name)
  defp requested_format(_params), do: {:error, :missing_format}

  defp format_error(%{"format" => name}) when is_binary(name),
    do: "Unknown report format #{inspect(name)}."

  defp format_error(_params), do: "Choose a report format to download."
end
