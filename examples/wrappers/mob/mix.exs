defmodule CountersMobile.MixProject do
  use Mix.Project
  def project, do: [app: :counters_mobile, version: "0.1.0", elixir: "~> 1.18",
    start_permanent: Mix.env() == :prod,
    deps: [{:bandit, "~> 1.8"}, {:plug, "~> 1.18"}, {:jason, "~> 1.4"}, {:mob, "== 0.9.27"}, {:mob_dev, "~> 0.7.31", only: :dev, runtime: false}], erlc_paths: ["src"], erlc_options: [:debug_info]]
  def application, do: [extra_applications: [:logger]]
end
