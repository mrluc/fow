defmodule Mix.Tasks.Fow.Gen.Mob do
  use Mix.Task
  @shortdoc "Generate a seamless Mob WebView wrapper from prepared native bundles"
  @moduledoc """
  Prepare every selected platform with `mix fow.bundle.prepare` first.
  Uses `.fow/native/<env>/<platform>` by default; `--bundle-dir` selects another parent.
  The WebView defaults to a pinned Git dependency. Override with `--webview-path`,
  or `--webview-git` plus `--webview-ref` (full commit SHA). These overrides can also
  be stored as `mob.webview` path/git/ref values in the manifest.
  """
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
    resolved = FogOfWar.Wrapper.Manifest.read!(manifest, opts[:env])
    default_output = Path.join([".fow/apps", "mob"] ++ List.wrap(resolved["environment"]))
    output = Path.expand(opts[:output] || default_output)

    FogOfWar.Wrapper.Generator.run!(:mob, manifest, output,
      env: opts[:env],
      force: opts[:force],
      bundle_dir: opts[:bundle_dir],
      webview_path: opts[:webview_path],
      webview_git: opts[:webview_git],
      webview_ref: opts[:webview_ref]
    )

    Mix.shell().info(
      "Created #{output}. See README.md and build.sh; no Phoenix server source copied."
    )
  end
end
