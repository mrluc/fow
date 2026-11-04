defmodule FogOfWar.MixProject do
  use Mix.Project

  def project do
    [
      app: :fow,
      version: "0.1.0",
      test_ignore_filters: [~r{/native/}],
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: [{:phoenix_live_view, "~> 1.2.13"}, {:jason, "~> 1.4"}, {:floki, "~> 0.38.0"}],
      description:
        "Fog of War: offline snapshots, caching, and read-only navigation for Phoenix LiveView web and WebView apps",
      package: [
        links: %{"Phoenix LiveView" => "https://phoenix-live-view.hexdocs.pm"},
        licenses: ["MIT"],
        files: ~w(lib priv package.json mix.exs README.md WRAPPERS.md LICENSE)
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
