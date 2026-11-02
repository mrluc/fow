Application.put_env(:fow, :dev_tools, true)
endpoint = FogOfWarFrontierWeb.Endpoint
config = Application.get_env(:fog_of_war_frontier, endpoint)
Application.put_env(:fog_of_war_frontier, endpoint,
  Keyword.merge(config,
    server: true, code_reloader: false,
    url: [host: "127.0.0.1", port: 47192],
    check_origin: ["//127.0.0.1:47192"],
    http: [ip: {127, 0, 0, 1}, port: 47192]
  ))
{:ok, _} = Application.ensure_all_started(:fog_of_war_frontier)
Process.sleep(:infinity)
