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

    get "/", PageController, :home
  end

  scope "/" do
    pipe_through :api

    openapi({:maestro, "openapi/maestro.yaml"}, handler: MaestroWeb.API.RunHandler)
    swagger_docs("/api/docs")
  end
end
