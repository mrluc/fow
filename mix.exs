defmodule FogOfWar.MixProject do
  use Mix.Project

  def project do
    [
      app: :fow,
      name: "Fog of War",
      version: "0.1.0",
      test_ignore_filters: [~r{/native/}],
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      aliases: [
        credo: "credo --strict",
        check: [
          "format --check-formatted",
          "compile --warnings-as-errors",
          "credo",
          "sobelow --exit",
          "test --warnings-as-errors"
        ]
      ],
      deps: [
        {:phoenix_live_view, "~> 1.2.13"},
        {:jason, "~> 1.4"},
        {:floki, "~> 0.38.0"},
        {:ex_doc, "~> 0.40", only: :dev, runtime: false},
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:sobelow, "~> 0.19.0", only: [:dev, :test], runtime: false},
        {:styler, "~> 1.12.0", only: [:dev, :test], runtime: false}
      ],
      docs: [
        main: "readme",
        logo: "docs/branding/fog-of-war.png",
        assets: %{"docs/screenshots" => "screenshots"},
        extras: [
          {"README.md", [title: "Fog of War"]},
          "docs/guides/example-apps-quickstart.md",
          {"docs/guides/rationale.md", [title: "Rationale"]}
        ],
        before_closing_head_tag: fn
          :html ->
            """
            <style>
              #top-content:has(.fow-overview-logo) > .top-heading { display: block; text-align: center; }
              #top-content:has(.fow-overview-logo) > .top-heading .icon-action { display: none; }
              .fow-overview-logo img { max-width: 100%; height: auto; }
            </style>
            """

          _ ->
            ""
        end,
        source_url: "https://github.com/mrluc/fow"
      ],
      description:
        "Fog of War: offline snapshots, caching, and read-only navigation for Phoenix LiveView web and WebView apps",
      package: [
        links: %{"Phoenix LiveView" => "https://phoenix-live-view.hexdocs.pm"},
        licenses: ["MIT"],
        files:
          ~w(lib priv package.json mix.exs README.md docs/guides/*.md docs/screenshots/*.jpg docs/branding/fog-of-war.png LICENSE)
      ]
    ]
  end

  def cli, do: [preferred_envs: [check: :test]]

  def application, do: [extra_applications: [:logger]]
end
