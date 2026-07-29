defmodule MaestroWeb.RedirectController do
  use MaestroWeb, :controller

  def workspaces(conn, _params) do
    redirect(conn, to: ~p"/workspaces")
  end
end
