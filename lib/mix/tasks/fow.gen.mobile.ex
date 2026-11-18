defmodule Mix.Tasks.Fow.Gen.Mobile do
  @shortdoc "Generate a seamless Mob WebView wrapper from prepared native bundles"
  @moduledoc """
  Generate an editable Mob project for a Phoenix site.

      mix fow.gen.mobileile --env android-dev

  Install the Mob generator archive and prepare a bundle for each platform selected in the manifest first. From the generated `.fow/<env>/projects/mobile/` directory, run `./build.sh --android` with an emulator running. `--output` chooses a project directory. `--force` replaces the generated project, including local edits.

  ## How it fits

  This generates the project only. It reads the prepared platform bundles and calls `FogOfWar.Wrapper.Generator.run!/4`. Run the generated build script afterward. For the complete Android or iOS development workflow, use `mix fow.mobile`.
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
          force: :boolean,
          bundle_dir: :string,
          webview_path: :string,
          webview_git: :string,
          webview_ref: :string
        ]
      )

    if rest != [] || invalid != [], do: Mix.raise("Invalid generator arguments")
    manifest = Path.expand(opts[:manifest] || ".fow.json")
    resolved = Manifest.read!(manifest, opts[:env])

    default_output =
      Path.join([".fow", resolved["environment"] || "default", "projects", "mobile"])

    output = Path.expand(opts[:output] || default_output)

    Generator.run!(:mob, manifest, output,
      env: opts[:env],
      force: opts[:force],
      bundle_dir: opts[:bundle_dir],
      webview_path: opts[:webview_path],
      webview_git: opts[:webview_git],
      webview_ref: opts[:webview_ref]
    )

    Mix.shell().info("Created #{output}. See README.md and build.sh; no Phoenix server source copied.")
  end
end
