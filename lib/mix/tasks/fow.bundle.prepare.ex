defmodule Mix.Tasks.Fow.Bundle.Prepare do
  use Mix.Task
  @shortdoc "Prepare executable startup HTML, gzip records and native assets"
  def run(args) do
    Mix.Task.run("app.config")

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          manifest: :string,
          env: :string,
          platform: :string,
          output: :string,
          debug: :boolean,
          base_url: :string
        ]
      )

    if rest != [] || invalid != [], do: Mix.raise("Invalid bundle arguments")
    platform = opts[:platform] || "android"
    unless platform in ["android", "ios"], do: Mix.raise("--platform must be android or ios")
    path = Path.expand(opts[:manifest] || ".fow.json")
    manifest = FogOfWar.Wrapper.Manifest.read!(path, opts[:env])
    project = Path.dirname(path)

    output =
      Path.expand(
        opts[:output] || ".fow/native/#{manifest["environment"] || "default"}/#{platform}",
        project
      )

    native = FogOfWar.Wrapper.NativeBundle.run!(manifest, project, output, platform, opts)

    Mix.shell().info(
      "Prepared #{platform} startup and #{map_size(native["files"])} resources in #{output}"
    )
  end
end
