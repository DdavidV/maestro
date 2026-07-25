defmodule Maestro.TestHttpPlug do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    {:ok, body, conn} = read_body(conn)
    conn = fetch_query_params(conn)
    route(conn, conn.request_path, body)
  end

  defp route(conn, "/echo", body) do
    payload =
      case body do
        "" -> nil
        json -> Jason.decode!(json)
      end

    json(conn, 200, %{
      "method" => conn.method,
      "payload" => payload,
      "query" => conn.query_params,
      "headers" => Map.new(conn.req_headers)
    })
  end

  defp route(conn, "/status/" <> code, _body) do
    send_resp(conn, String.to_integer(code), "")
  end

  defp route(conn, "/text", _body) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "hello world")
  end

  defp route(conn, "/slow", _body) do
    Process.sleep(1000)
    send_resp(conn, 200, "too slow")
  end

  defp route(conn, _path, _body), do: send_resp(conn, 404, "not found")

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
