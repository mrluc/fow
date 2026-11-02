defmodule Mix.Tasks.Fow.Gen.Mob do
  use Mix.Task
  @shortdoc "Generate a mob WebView wrapper from .fow.json and its public export"
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [manifest: :string, output: :string])
    if rest != [] || invalid != [], do: Mix.raise("Invalid generator arguments")
    manifest = Path.expand(opts[:manifest] || ".fow.json")
    output = Path.expand(opts[:output] || ".fow/apps/mob")
    FogOfWar.Wrapper.Generator.run!(:mob, manifest, output)

    Mix.shell().info(
      "Created #{output}. See README.md and build.sh; no Phoenix server source copied."
    )
  end
end
