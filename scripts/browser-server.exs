Code.require_file("browser-fixtures.exs", __DIR__)
Application.put_env(:fow, :dev_tools, true)
endpoint = FogOfWarBasicWeb.Endpoint
config = Application.get_env(:fog_of_war_basic, endpoint)

Application.put_env(
  :fog_of_war_basic,
  endpoint,
  Keyword.merge(config,
    server: true,
    code_reloader: false,
    url: [host: "127.0.0.1", port: 47182],
    check_origin: ["//127.0.0.1:47182", "//127.0.0.1:47183"],
    http: [ip: {127, 0, 0, 1}, port: 47182]
  )
)

{:ok, _} = Application.ensure_all_started(:fog_of_war_basic)
{:ok, _} = Bandit.start_link(plug: FogOfWar.BrowserFixtures, ip: {127, 0, 0, 1}, port: 47183)
Process.sleep(:infinity)
