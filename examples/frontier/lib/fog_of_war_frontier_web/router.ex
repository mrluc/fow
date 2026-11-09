defmodule FogOfWarFrontierWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug FogOfWarFrontierWeb.PlayerSession
    plug :fetch_live_flash
    plug :put_root_layout, html: {FogOfWarFrontierWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :inspector do
    plug FogOfWarFrontierWeb.InspectorAuth
  end

  scope "/", FogOfWarFrontierWeb do
    pipe_through [:browser, :inspector]

    live_session :game_debug,
      root_layout: {FogOfWarFrontierWeb.Layouts, :debug},
      on_mount: [FogOfWarFrontierWeb.InspectorAuth] do
      live "/inspector", GameInspectorLive
      if Application.compile_env(:fog_of_war_frontier, :dev_routes, false) do
        live "/dev/game", GameInspectorLive
      end
    end
  end

  scope "/", FogOfWarFrontierWeb do
    pipe_through :browser
    live "/multi", MultiLive, :home
    live "/multi/lat/:lat/lon/:lon", MultiLive, :sector
    live "/", MultiLive, :home
    live "/lat/:lat/lon/:lon", MapLive, :sector
  end
end
