defmodule Mix.Tasks.Fow.Gen.Elixirkit do
  use Mix.Task
  @shortdoc "Generate a elixirkit WebView wrapper from .fow.json and its public export"
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [manifest: :string, output: :string])
    if rest != [] || invalid != [], do: Mix.raise("Invalid generator arguments")
    manifest = Path.expand(opts[:manifest] || ".fow.json")
    output = Path.expand(opts[:output] || ".fow/apps/elixirkit")
    FogOfWar.Wrapper.Generator.run!(:elixirkit, manifest, output)

    Mix.shell().info(
      "Created #{output}. See README.md and build.sh; no Phoenix server source copied."
    )
  end
end
