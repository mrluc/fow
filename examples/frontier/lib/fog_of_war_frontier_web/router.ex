defmodule FogOfWarFrontierWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FogOfWarFrontierWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", FogOfWarFrontierWeb do
    pipe_through :browser
    live "/", MapLive, :home
    live "/sectors/:id", MapLive, :sector
  end
end
