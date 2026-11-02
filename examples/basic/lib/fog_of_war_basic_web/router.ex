defmodule FogOfWarBasicWeb.Router do
  use FogOfWarBasicWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FogOfWarBasicWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FogOfWarBasicWeb do
    pipe_through :browser

    live_session :counters do
      live "/", CounterIndexLive
      live "/counters/:id", CounterLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", FogOfWarBasicWeb do
  #   pipe_through :api
  # end
end
