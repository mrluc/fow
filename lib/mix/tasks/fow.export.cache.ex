defmodule Mix.Tasks.Fow.Export.Cache do
  @shortdoc "Export public FoW regions as binary gzip files and a route index (no browser)"
  @moduledoc """
  Export offline route snapshots without building an app.

      mix fow.export.cache --env dev --output .fow/dev/bundles/cache

  Run from the Phoenix project with the public website reachable. The output contains an index and gzip payloads for an importer. Use `--debug` to retain capture HTML for troubleshooting. For generated native apps, `mix fow.bundle.prepare` adds the platform-specific startup document and assets.

  ## How it fits

  This is a lower-level capture tool for inspecting or consuming gzip route records. Native bundle preparation calls the same `FogOfWar.Wrapper.CacheExport` module directly; running this task separately is unnecessary for a normal build.
  """
  use Mix.Task

  alias FogOfWar.Wrapper.CacheExport
  alias FogOfWar.Wrapper.Manifest

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
    manifest = Manifest.read!(path, opts[:env])

    output =
      Path.expand(opts[:output] || manifest["public"]["bundle"] <> "-cache", Path.dirname(path))

    index =
      CacheExport.run!(manifest, output,
        base_url: opts[:base_url],
        debug: opts[:debug]
      )

    bytes = Enum.reduce(index["pages"], 0, fn {_, page}, sum -> sum + page["compressedBytes"] end)

    Mix.shell().info(
      "Exported #{map_size(index["pages"])} public FoW records (#{bytes} gzip bytes) to #{output}. No browser or IndexedDB import used."
    )
  end
end
