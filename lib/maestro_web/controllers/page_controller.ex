defmodule MaestroWeb.PageController do
  use MaestroWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
