defmodule Mix.Tasks.Fow.Build.Desktop do
  use Mix.Task
  @shortdoc "Build a generated ElixirKit desktop project"
  @moduledoc """
  Compile an already generated desktop project on macOS.

      mix fow.build.desktop --env dev

  Run from the Phoenix project. The task finds the generated project through the manifest environment, or accepts its directory via `--output`. It requires Rust, the Tauri CLI and Xcode command-line tools. Use the printed .app path with `mix fow.install.desktop` or open it directly.

  ## How it fits

  This is the build step used by `mix fow.desktop`. Both call `FogOfWar.Wrapper.Workflow.build_elixirkit!/2` directly. Use it separately after generating or editing a desktop project.
  """
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [manifest: :string, env: :string, output: :string])

    if rest != [] || invalid != [], do: Mix.raise("Invalid build arguments")
    manifest = Path.expand(opts[:manifest] || ".fow.json")
    project = FogOfWar.Wrapper.Workflow.project_path(manifest, :elixirkit, opts)
    app = FogOfWar.Wrapper.Workflow.build_elixirkit!(project)
    Mix.shell().info("Built #{app}")
  end
end
