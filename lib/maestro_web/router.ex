defmodule MaestroWeb.Router do
  use MaestroWeb, :router
  use Openapi.Phoenix

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MaestroWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json", "html"]
  end

  scope "/", MaestroWeb do
    pipe_through :browser

    get "/", RedirectController, :workspaces

    live_session :workspaces_index do
      live "/workspaces", WorkspaceLive.Index, :index
    end

    scope "/workspace/:workspace_id" do
      get "/reports/:run_id/download", ReportController, :download
    end

    live_session :workspace, on_mount: MaestroWeb.WorkspaceOnMount do
      scope "/workspace/:workspace_id" do
        live "/", WorkspaceLive.Explorer, :dashboard
        live "/run", RunLive.New, :new
        live "/history", RunLive.Index, :index
        live "/history/:run_id", RunLive.Show, :show
        live "/reports/:run_id", ReportLive.Show, :show
        live "/:kind", WorkspaceLive.Explorer, :index
        live "/:kind/new", WorkspaceLive.Form, :new
        live "/:kind/edit/*path", WorkspaceLive.Form, :edit
        live "/:kind/*path", WorkspaceLive.Explorer, :show
      end
    end
  end

  scope "/" do
    pipe_through :api

    openapi({:maestro, "openapi/maestro.yaml"}, handler: MaestroWeb.API.RunHandler)
    swagger_docs("/api/docs")
  end
end
