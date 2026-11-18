defmodule Mix.Tasks.Fow.Bundle.Prepare do
  @shortdoc "Prepare executable startup HTML, gzip records and native assets"
  @moduledoc """
  Capture the public startup document and assets for one WebView platform.

      mix fow.bundle.prepare --env android-dev --platform android

  Run from the Phoenix project with the selected website reachable. Output goes to `.fow/<env>/bundles/<platform>/`. Use `--platform apple` for the desktop generator, or `--platform ios` for Mob on iOS. Move an existing bundle aside or choose another `--output`. The macOS shortcut `mix fow.desktop` already prepares its bundle.

  ## How it fits

  This is a lower-level step. For macOS, `mix fow.desktop` calls `FogOfWar.Wrapper.NativeBundle.run!/5` itself. For mobile, run this task before `mix fow.gen.mobile`, once per selected platform.
  """

  use Mix.Task

  alias FogOfWar.Wrapper.Manifest
  alias FogOfWar.Wrapper.NativeBundle

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

    if platform not in ["android", "ios", "apple"],
      do: Mix.raise("--platform must be android, ios or apple")

    path = Path.expand(opts[:manifest] || ".fow.json")
    manifest = Manifest.read!(path, opts[:env])
    project = Path.dirname(path)

    output =
      Path.expand(
        opts[:output] || ".fow/#{manifest["environment"] || "default"}/bundles/#{platform}",
        project
      )

    native = NativeBundle.run!(manifest, project, output, platform, opts)

    Mix.shell().info("Prepared #{platform} startup and #{map_size(native["files"])} resources in #{output}")
  end
end
