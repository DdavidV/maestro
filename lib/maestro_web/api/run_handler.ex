defmodule MaestroWeb.API.RunHandler do
  @moduledoc """
  Handler module for `priv/openapi/maestro.yaml`.
  Each function here corresponds 1:1 to that spec's `operationId`s
  (underscored, per `Openapi.DispatchPlug`'s normalization), and is a
  thin translation from a rendered `Plug.Conn` to the matching
  `Maestro.*` function and back a REST wrapper.
  """

  import Plug.Conn

  @doc """
  createRun: POST /run -> Maestro.run/1.

  The request body is a bare JSON array, which `Plug.Parsers.JSON` parses
  into `params["_json"]` rather than `params` itself (a top-level JSON
  array can't be merged into `conn.params`, which is always a map).
  """
  def create_run(conn, %{"_json" => entries}) when is_list(entries) do
    case Maestro.run(entries) do
      {:ok, run_id} ->
        json(conn, 202, %{run_id: run_id})

      {:error, resolve_errors} ->
        json(conn, 422, %{errors: Enum.map(resolve_errors, &resolve_error_entry/1)})
    end
  end

  def create_run(conn, _params) do
    json(conn, 400, %{error: "request body must be an array"})
  end

  @doc "createTestPlanRun: POST /test-plan/{name}/run -> Maestro.run_test_plan/1."
  def create_test_plan_run(conn, %{"name" => name}) do
    case Maestro.run_test_plan(name) do
      {:ok, run_id} ->
        json(conn, 202, %{run_id: run_id})

      {:error, {:test_plan_not_found, ^name}} ->
        json(conn, 404, %{error: %{test_plan_not_found: name}})

      {:error, resolve_errors} ->
        json(conn, 422, %{errors: Enum.map(resolve_errors, &resolve_error_entry/1)})
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
  getRunReport: GET /runs/{run_id}/report -> Maestro.render_report/1
  (always the configured default layout no layout override over REST).
  """
  def get_run_report(conn, %{"run_id" => run_id}) do
    case Maestro.render_report(run_id) do
      {:ok, html} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, html)

      {:error, :not_found} ->
        json(conn, 404, %{error: :not_found})
    end
  end

  @doc """
  createRunReport: POST /runs/{run_id}/report -> Maestro.generate_report/1
  (always the configured default layout).
  """
  def create_run_report(conn, %{"run_id" => run_id}) do
    case Maestro.generate_report(run_id) do
      :ok ->
        path = Path.join(Maestro.Report.report_dir(), "maestro_report_#{run_id}.html")
        json(conn, 201, %{run_id: run_id, path: path})

      {:error, :not_found} ->
        json(conn, 404, %{error: :not_found})

      {:error, {:write_failed, reason}} ->
        json(conn, 500, %{error: %{write_failed: inspect(reason)}})
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
