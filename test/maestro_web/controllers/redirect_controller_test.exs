defmodule MaestroWeb.RedirectControllerTest do
  use MaestroWeb.ConnCase

  test "GET / redirects to /workspaces", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/workspaces"
  end
end
