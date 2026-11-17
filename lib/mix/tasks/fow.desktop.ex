defmodule Mix.Tasks.Fow.Desktop do
  use Mix.Task
  @shortdoc "Prepare, build and install the macOS WebKit app"
  @moduledoc """
  Build and install the macOS wrapper in one step.

      mix fow.desktop --env dev

  Run from the Phoenix project while the selected website is reachable. The task prepares the Apple bundle, generates the project, builds the .app and installs it to ~/Applications. Use `--force` to replace existing outputs or `--applications` to choose another installation directory. Use the separate generator and build tasks when keeping native edits.

  ## How it fits

  This is the complete macOS workflow. Internally it calls `FogOfWar.Wrapper.Workflow.desktop!/2`, which invokes bundle preparation, generation, build and installation functions directly. It does not invoke the other Mix tasks.
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
