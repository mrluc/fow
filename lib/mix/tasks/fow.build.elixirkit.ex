defmodule Mix.Tasks.Fow.Build.Elixirkit do
  use Mix.Task
  @shortdoc "Build a generated ElixirKit desktop project"
  @moduledoc "Run `mix fow.build.elixirkit --output path/to/project`; manifest/env select the default generated project."
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
