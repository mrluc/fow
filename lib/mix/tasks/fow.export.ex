defmodule Mix.Tasks.Fow.Export do
  use Mix.Task
  @shortdoc "Export explicitly public pages and assets for native offline startup"
  def run(args) do
    Mix.Task.run("app.config")

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          manifest: :string,
          output: :string,
          base_url: :string,
          env: :string,
          debug: :boolean
        ]
      )

    if rest != [] || invalid != [], do: Mix.raise("Invalid export arguments")
    manifest_path = Path.expand(opts[:manifest] || ".fow.json")
    manifest = FogOfWar.Wrapper.Manifest.read!(manifest_path, opts[:env])
    root = Path.dirname(manifest_path)
    out = Path.expand(opts[:output] || manifest["public"]["bundle"], root)

    result =
      FogOfWar.Wrapper.Export.run!(manifest, root, out,
        base_url: opts[:base_url],
        debug: opts[:debug]
      )

    Mix.shell().info(
      "Exported #{map_size(result["pages"])} public pages and #{map_size(result["assets"])} assets to #{out}. No cookies or server source copied."
    )
  end
end
