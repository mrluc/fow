defmodule Mix.Tasks.Fow.Manifest do
  use Mix.Task
  @shortdoc "Derive a reviewable .fow.json manifest from the current Phoenix project"
  @moduledoc """
  Create .fow.json before building a native app.

      mix fow.manifest --name "My App" --url http://127.0.0.1:4000

  Run from the Phoenix project. Review the generated startup route, public preload routes, website origin and app identity before committing the file. Use `--output` for another filename and `--force` to overwrite it.

  ## How it fits

  Run this once to create the configuration used by the other tasks. The other tasks read the manifest; they do not invoke this generator automatically.
  """
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          endpoint: :string,
          url: :string,
          public: [:string, :keep],
          name: :string,
          slug: :string,
          identifier: :string,
          output: :string,
          force: :boolean
        ]
      )

    if rest != [] || invalid != [],
      do: Mix.raise("Invalid manifest arguments: #{inspect(rest ++ invalid)}")

    Mix.Task.run("compile")
    manifest = FogOfWar.Wrapper.Manifest.discover(opts)
    path = opts[:output] || ".fow.json"
    FogOfWar.Wrapper.Manifest.write!(path, manifest, opts[:force] || false)

    Mix.shell().info(
      "Created #{path}. Review identity, origin, icons and startup.path and preload.paths before exporting."
    )
  end
end
