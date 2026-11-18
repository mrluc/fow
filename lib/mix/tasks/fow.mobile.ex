defmodule Mix.Tasks.Fow.Mobile do
  @shortdoc "Prepare, generate, build and deploy a mobile app"
  @moduledoc """
  Build and deploy a development wrapper to a running device or emulator.

      mix fow.mobile --env android-dev --platform android

  Run from the Phoenix project while the capture site is reachable.
  Select a device with `--device` when more than one is available.
  For local Android origins, set up adb reverse before deploying.
  Use `--force` to replace prepared bundles and generated source.
  """

  use Mix.Task

  alias FogOfWar.Wrapper.Generator
  alias FogOfWar.Wrapper.Manifest
  alias FogOfWar.Wrapper.NativeBundle
  alias FogOfWar.Wrapper.Output
  alias FogOfWar.Wrapper.Workflow

  def run(args) do
    Mix.Task.run("app.config")

    opts = parse_args!(args)
    platform = opts[:platform] || "android"
    if platform not in ["android", "ios"], do: Mix.raise("--platform must be android or ios")
    path = Path.expand(opts[:manifest] || ".fow.json")
    manifest = Manifest.read!(path, opts[:env])
    root = Path.dirname(path)
    bundles = Path.join([root, ".fow", manifest["environment"] || "default", "bundles"])
    project = Workflow.project_path(path, :mob, opts)
    platforms = get_in(manifest, ["mob", "platforms"]) || ["android", "ios"]

    if platform not in platforms,
      do: Mix.raise("Selected manifest environment excludes #{platform}")

    Output.validate!(project, [root, bundles])
    if File.exists?(project) && !opts[:force], do: Mix.raise("Destination exists: #{project}")

    prepare_bundles!(platforms, bundles, manifest, root, project, opts)
    Generator.run!(:mob, path, project, Keyword.put(opts, :bundle_dir, bundles))
    deploy!(project, platform, opts[:device])
  end

  defp parse_args!(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          manifest: :string,
          env: :string,
          platform: :string,
          device: :string,
          output: :string,
          force: :boolean,
          base_url: :string,
          webview_path: :string
        ]
      )

    if rest != [] || invalid != [], do: Mix.raise("Invalid mobile arguments")

    opts
  end

  defp prepare_bundles!(platforms, bundles, manifest, root, project, opts) do
    for selected <- platforms do
      output = Path.join(bundles, selected)

      Output.replace!(output, [force: opts[:force], protected: [root, project]], fn stage ->
        File.rmdir!(stage)
        NativeBundle.run!(manifest, root, stage, selected, base_url: opts[:base_url])
      end)
    end
  end

  defp deploy!(project, platform, serial) do
    device = if serial, do: ["--device", serial], else: []

    {_, status} =
      System.cmd("bash", ["build.sh", "--" <> platform] ++ device,
        cd: project,
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0, do: Mix.raise("Mobile deployment exited with status #{status}")
  end
end
