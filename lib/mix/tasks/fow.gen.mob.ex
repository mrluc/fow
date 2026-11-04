defmodule Mix.Tasks.Fow.Gen.Mob do
  use Mix.Task
  @shortdoc "Generate a mob WebView wrapper from .fow.json and its public export"
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [manifest: :string, output: :string, env: :string, force: :boolean]
      )

    if rest != [] || invalid != [], do: Mix.raise("Invalid generator arguments")
    manifest = Path.expand(opts[:manifest] || ".fow.json")
    resolved = FogOfWar.Wrapper.Manifest.read!(manifest, opts[:env])
    default_output = Path.join([".fow/apps", "mob"] ++ List.wrap(resolved["environment"]))
    output = Path.expand(opts[:output] || default_output)
    FogOfWar.Wrapper.Generator.run!(:mob, manifest, output, env: opts[:env], force: opts[:force])

    Mix.shell().info(
      "Created #{output}. See README.md and build.sh; no Phoenix server source copied."
    )
  end
end
