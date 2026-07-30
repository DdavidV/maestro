defmodule MaestroWeb.ReportController do
  @moduledoc """
  Downloads a run's report as a standalone HTML file.

  Calls `Maestro.render_report/1` directly, so the download always
  reflects the run's current state including a still-running run
  rather than whatever was last auto-generated to disk after the run finished.
  """

  use MaestroWeb, :controller

  alias Maestro.Core.Runner

  def download(conn, %{"workspace_id" => workspace_id, "run_id" => run_id}) do
    with {:ok, ^workspace_id} <- Runner.workspace_id(run_id),
         {:ok, html} <- Maestro.render_report(run_id) do
      conn
      |> put_resp_content_type("text/html")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="maestro_report_#{run_id}.html")
      )
      |> send_resp(200, html)
    else
      _not_found_or_wrong_workspace ->
        conn
        |> put_flash(:error, "Run #{run_id} not found.")
        |> redirect(to: ~p"/workspace/#{workspace_id}")
    end
  end
end
