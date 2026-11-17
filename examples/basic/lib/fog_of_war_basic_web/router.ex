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

  pipeline :demo_account do
    plug :require_demo_account
  end

  scope "/" do
    pipe_through [:browser, :demo_account]
    post "/_fow/account-key", FogOfWar.AccountKeyEndpoint, []
  end

  scope "/", FogOfWarBasicWeb do
    pipe_through :browser

    post "/demo/login", DemoSession, :login
    delete "/demo/logout", DemoSession, :logout

    live_session :counters, on_mount: FogOfWarBasicWeb.DemoSession do
      live "/log-in", LoginLive
      live "/", CounterIndexLive
      live "/counters/:id", CounterLive
    end
  end

  scope "/", FogOfWarBasicWeb do
    pipe_through [:browser, :demo_account]

    live_session :demo_profile, on_mount: {FogOfWarBasicWeb.DemoSession, :require_account} do
      live "/profile", ProfileLive
    end
  end

  defp require_demo_account(conn, opts),
    do: FogOfWarBasicWeb.DemoSession.require_account(conn, opts)

  # Other scopes may use custom stacks.
  # scope "/api", FogOfWarBasicWeb do
  #   pipe_through :api
  # end
end
