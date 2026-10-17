defmodule MaestroWeb.API.RunHandler do
  @moduledoc """
  Handler module for `priv/openapi/maestro.yaml`.
  Each function here corresponds 1:1 to that spec's `operationId`s
  (underscored, per `Openapi.DispatchPlug`'s normalization), and is a
  thin translation from a rendered `Plug.Conn` to the matching
  `Maestro.*` function and back a REST wrapper.
  """

  import Plug.Conn

  alias Maestro.Report.Format

  @doc """
  createRun: POST /run -> Maestro.run/2.

  `workspace_id` selects an already-registered workspace; `entries` is the
  same list `Maestro.run/2` itself takes.
  """
  def create_run(conn, %{"workspace_id" => workspace_id, "entries" => entries})
      when is_binary(workspace_id) and is_list(entries) do
    with {:ok, workspace} <- fetch_workspace(workspace_id) do
      case Maestro.run(workspace, entries) do
        {:ok, run_id} ->
          json(conn, 202, %{run_id: run_id})

        {:error, resolve_errors} ->
          json(conn, 422, %{errors: Enum.map(resolve_errors, &resolve_error_entry/1)})
      end
    else
      {:error, :workspace_not_found} ->
        json(conn, 404, %{error: %{workspace_not_found: workspace_id}})
    end
  end

  def create_run(conn, _params) do
    json(conn, 400, %{error: "request body must have workspace_id (string) and entries (array)"})
  end

  @doc "createTestPlanRun: POST /workspaces/{workspace_id}/test-plan/{name}/run -> Maestro.run_test_plan/2."
  def create_test_plan_run(conn, %{"workspace_id" => workspace_id, "name" => name}) do
    with {:ok, workspace} <- fetch_workspace(workspace_id) do
      case Maestro.run_test_plan(workspace, name) do
        {:ok, run_id} ->
          json(conn, 202, %{run_id: run_id})

        {:error, {:test_plan_not_found, ^name}} ->
          json(conn, 404, %{error: %{test_plan_not_found: name}})

        {:error, resolve_errors} ->
          json(conn, 422, %{errors: Enum.map(resolve_errors, &resolve_error_entry/1)})
      end
    else
      {:error, :workspace_not_found} ->
        json(conn, 404, %{error: %{workspace_not_found: workspace_id}})
    end
  end

  @doc "getRunStatus: GET /runs/{run_id}/status -> Maestro.status/1."
  def get_run_status(conn, %{"run_id" => run_id}) do
    case Maestro.status(run_id) do
      {:ok, progress} -> json(conn, 200, progress)
      {:error, :not_found} -> json(conn, 404, %{error: :not_found})
    end
  end

  @doc """
  getRunResult: GET /runs/{run_id}?suite_id=&testcase_id= ->
  Maestro.result/1,2,3, chosen by which query params are present.
  """
  def get_run_result(conn, %{"run_id" => run_id} = params) do
    result =
      case {Map.get(params, "suite_id"), Map.get(params, "testcase_id")} do
        {nil, _} -> Maestro.result(run_id)
        {suite_id, nil} -> Maestro.result(run_id, suite_id)
        {suite_id, testcase_id} -> Maestro.result(run_id, suite_id, testcase_id)
      end

    case result do
      {:ok, result} -> json(conn, 200, result)
      {:error, :not_found} -> json(conn, 404, %{error: :not_found})
    end
  end

  @doc """
  getRunReport: GET /runs/{run_id}/report?format= -> Maestro.render_report/2.

  `format` names any `Maestro.Report.Format.available/0` format (`html`,
  `junit`, or a host's own); omitted, it's `Maestro.Report.Format.default/0`.
  Served with that format's own content type.
  """
  def get_run_report(conn, %{"run_id" => run_id} = params) do
    with {:ok, format} <- requested_format(params),
         {:ok, body} <- Maestro.render_report(run_id, format) do
      conn
      |> put_resp_content_type(Format.content_type(format))
      |> send_resp(200, body)
    else
      {:error, :unknown_format} -> unknown_format(conn, params)
      {:error, :not_found} -> json(conn, 404, %{error: :not_found})
    end
  end

  @doc """
  createRunReport: POST /runs/{run_id}/report?format= -> writes reports to disk.

  With `format`, writes just that format (`Maestro.generate_report/2`).
  Without it, writes every configured format (`Maestro.generate_reports/1`),
  same as what happens automatically after a run. `path` is the first
  written file (the HTML report, by default); `paths` maps every written
  format's name to its file.
  """
  def create_run_report(conn, %{"run_id" => run_id} = params) do
    case Map.fetch(params, "format") do
      {:ok, _name} -> create_one_report(conn, run_id, params)
      :error -> create_all_reports(conn, run_id)
    end
  end

  defp create_one_report(conn, run_id, params) do
    with {:ok, format} <- requested_format(params),
         :ok <- Maestro.generate_report(run_id, format) do
      {:ok, path} = Maestro.Report.report_path(run_id, format)
      json(conn, 201, %{run_id: run_id, path: path, paths: %{Format.name(format) => path}})
    else
      {:error, :unknown_format} ->
        unknown_format(conn, params)

      {:error, :not_found} ->
        json(conn, 404, %{error: :not_found})

      {:error, {:write_failed, reason}} ->
        json(conn, 500, %{error: %{write_failed: inspect(reason)}})
    end
  end

  defp create_all_reports(conn, run_id) do
    case Maestro.generate_reports(run_id) do
      {:ok, written} ->
        paths = Map.new(written, fn {format, path} -> {Format.name(format), path} end)
        first = Enum.find(Format.configured(), &Map.has_key?(written, &1))
        json(conn, 201, %{run_id: run_id, path: written[first], paths: paths})

      {:error, :not_found} ->
        json(conn, 404, %{error: :not_found})

      {:error, failures} ->
        failed =
          Map.new(failures, fn {format, reason} -> {Format.name(format), inspect(reason)} end)

        json(conn, 500, %{error: %{write_failed: failed}})
    end
  end

  defp requested_format(%{"format" => name}) when is_binary(name), do: Format.find(name)
  defp requested_format(_params), do: {:ok, Format.default()}

  defp unknown_format(conn, params) do
    json(conn, 400, %{
      error: %{
        unknown_format: params["format"],
        available: Enum.map(Format.available(), &Format.name/1)
      }
    })
  end

  defp fetch_workspace(workspace_id) do
    case Maestro.Workspaces.get(workspace_id) do
      {:ok, workspace} -> {:ok, workspace}
      {:error, :not_found} -> {:error, :workspace_not_found}
    end
  end

  defp resolve_error_entry({index, reason}) do
    %{index: index, reason: stringify_reason(reason)}
  end

  defp stringify_reason(reason) when is_atom(reason) or is_binary(reason), do: reason
  defp stringify_reason(reason), do: inspect(reason)

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
