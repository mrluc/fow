defmodule Mix.Tasks.Fow.Manifest do
  use Mix.Task
  @shortdoc "Derive a reviewable .fow.json manifest from the current Phoenix project"
  @moduledoc """
  Run inside a Phoenix app: `mix fow.manifest --url https://example.com --public /`.
  Public routes are explicitly opted into export; discovered routes are informational.
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
      "Created #{path}. Review identity, origin, icons and public.paths before exporting."
    )
  end
end
