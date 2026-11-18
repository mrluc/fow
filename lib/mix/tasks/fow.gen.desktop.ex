defmodule Mix.Tasks.Fow.Gen.Desktop do
  @shortdoc "Generate a macOS project from a prepared Apple bundle"
  @moduledoc """
  Generate desktop source when you want to build separately or customize the host.

      mix fow.gen.desktop --env dev

  Prepare the Apple bundle first with `mix fow.bundle.prepare --env dev --platform apple`. Then build with `mix fow.build.desktop --env dev`. Use `--output` to keep the project outside the generated directory. The default input is `.fow/<env>/bundles/apple`; use `--bundle-dir` to override it. For the ordinary macOS workflow, use `mix fow.desktop`.

  ## How it fits

  This is the generation step in the macOS workflow. `mix fow.desktop` calls the same `FogOfWar.Wrapper.Generator.run!/4` function directly, rather than invoking this task. Use this task when you want the source project as a separate step.
  """

  use Mix.Task

  alias FogOfWar.Wrapper.Generator
  alias FogOfWar.Wrapper.Manifest

  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          manifest: :string,
          output: :string,
          env: :string,
          bundle_dir: :string,
          force: :boolean
        ]
      )

    if rest != [] || invalid != [], do: Mix.raise("Invalid generator arguments")
    manifest = Path.expand(opts[:manifest] || ".fow.json")
    resolved = Manifest.read!(manifest, opts[:env])

    default_output =
      Path.join([".fow", resolved["environment"] || "default", "projects", "desktop"])

    output = Path.expand(opts[:output] || default_output)

    Generator.run!(:elixirkit, manifest, output,
      env: opts[:env],
      bundle_dir: opts[:bundle_dir],
      force: opts[:force]
    )

    Mix.shell().info("Created #{output}. See README.md and build.sh; no Phoenix server source copied.")
  end
end
