defmodule Mix.Tasks.Fow.Export.Cache do
  use Mix.Task
  @shortdoc "Export public FoW regions as binary gzip files and a route index (no browser)"
  @moduledoc """
  Fetches initial server-rendered HTML from the selected site's public paths.
  It does not read a browser profile, execute hooks, or import into IndexedDB.
  Use `--env NAME` for manifest overrides and `--debug` to retain intermediate HTML.
  """
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

    if rest != [] || invalid != [], do: Mix.raise("Invalid cache export arguments")
    path = Path.expand(opts[:manifest] || ".fow.json")
    manifest = FogOfWar.Wrapper.Manifest.read!(path, opts[:env])

    output =
      Path.expand(opts[:output] || manifest["public"]["bundle"] <> "-cache", Path.dirname(path))

    index =
      FogOfWar.Wrapper.CacheExport.run!(manifest, output,
        base_url: opts[:base_url],
        debug: opts[:debug]
      )

    bytes = Enum.reduce(index["pages"], 0, fn {_, page}, sum -> sum + page["compressedBytes"] end)

    Mix.shell().info(
      "Exported #{map_size(index["pages"])} public FoW records (#{bytes} gzip bytes) to #{output}. No browser or IndexedDB import used."
    )
  end
end
