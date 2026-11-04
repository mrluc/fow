defmodule Mix.Tasks.Fow.Desktop do
  use Mix.Task
  @shortdoc "Export, generate, build and install a local macOS desktop app"
  @moduledoc "Run `mix fow.desktop --force` to replace generated artifacts and the installed app. `--output` is the generated source project; `--applications` selects the installation directory."
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
