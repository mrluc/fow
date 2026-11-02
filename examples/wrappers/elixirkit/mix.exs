defmodule CountersDesktop.MixProject do
  use Mix.Project
  def project, do: [app: :counters_desktop, version: "0.1.0", elixir: "~> 1.18",
    start_permanent: Mix.env() == :prod,
    deps: [{:bandit, "~> 1.8"}, {:plug, "~> 1.18"}, {:jason, "~> 1.4"}, {:elixirkit, github: "livebook-dev/elixirkit", ref: "16d19dd3fe7ad0c0e38a1667a90ed7962ed477c7"}], releases: [counters_desktop: [steps: [:assemble, &ElixirKit.Release.codesign/1], entitlements: "src-tauri/App.entitlements"]]]
  def application, do: [mod: {CountersDesktop.Application, []}, extra_applications: [:logger]]
end
