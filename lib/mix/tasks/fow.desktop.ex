defmodule Mix.Tasks.Fow.Desktop do
  use Mix.Task
  @shortdoc "Prepare, build and install the macOS WebKit app"
  @moduledoc """
  Prepare the Apple bundle, generate and build the macOS app, and register it with Spotlight.

  Run `mix fow.desktop --force` while the capture site is reachable. The flag replaces
  the prepared bundle, generated project, and installed app. Use `--output` to select
  the generated project and `--applications` to select the installation directory
  (defaults to `~/Applications`).
  """
  def run(args) do
    Mix.Task.run("app.config")

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          manifest: :string,
          env: :string,
          output: :string,
          applications: :string,
          force: :boolean,
          base_url: :string
        ]
      )

    if rest != [] || invalid != [], do: Mix.raise("Invalid desktop arguments")
    destination = FogOfWar.Wrapper.Workflow.desktop!(opts[:manifest] || ".fow.json", opts)
    Mix.shell().info("Installed #{destination}; launch it from Spotlight")
  end
end
