defmodule MaestroWeb.LiveViewCase do
  @moduledoc """
  Test case for LiveView tests, mirroring `MaestroWeb.ConnCase`'s shape but
  also importing `Phoenix.LiveViewTest` for `live/2`, `render_click/2`, etc.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint MaestroWeb.Endpoint

      use MaestroWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import MaestroWeb.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
