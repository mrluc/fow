# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fog_of_war_frontier,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :fog_of_war_frontier, FogOfWarFrontierWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FogOfWarFrontierWeb.ErrorHTML, json: FogOfWarFrontierWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FogOfWarFrontier.PubSub,
  live_view: [signing_salt: "F+rnsFHh"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  fog_of_war_frontier: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    # Local path dependency: include the directory containing the fow package.
    # A Hex install in deps/fow needs only the normal ../deps search path.
    env: %{
      "NODE_PATH" => [
        Path.expand("../deps", __DIR__),
        Path.expand("../../../..", __DIR__),
        Mix.Project.build_path()
      ]
    }
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
