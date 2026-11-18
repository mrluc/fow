defmodule FogOfWar.Wrapper.Generator do
  @moduledoc """
  Creates a standalone native source project from a resolved manifest and prepared bundle. Generation copies the inputs and writes the host project. The generated build script handles native compilation.

  ## How it fits

  Called by both generator Mix tasks and directly by `FogOfWar.Wrapper.Workflow.desktop!/2`. It creates source projects; `Workflow` handles desktop building and installation.
  """
  alias FogOfWar.Wrapper.Export
  alias FogOfWar.Wrapper.Manifest
  alias FogOfWar.Wrapper.Output

  @mob_webview_git "https://github.com/mrluc/fow_webview_mob.git"
  @mob_webview_ref "1be07da3604a64bc6ef11c87858c3c9ad372e80b"

  @doc "Generate a Mob or ElixirKit project at the output path. Read the selected environment from the manifest file. Pass `:force` to replace an existing generated project after staging succeeds."
  def run!(target, manifest_path, output, opts \\ []) when target in [:mob, :elixirkit] do
    manifest = Manifest.read!(manifest_path, opts[:env])
    root = Path.dirname(Path.expand(manifest_path))

    {bundle_path, native_bundles, webview_path} =
      if target == :mob do
        native_root =
          Path.expand(
            opts[:bundle_dir] || ".fow/#{manifest["environment"] || "default"}/bundles",
            root
          )

        native_bundles = read_native_bundles!(native_root, manifest)
        {dependency, path} = webview_dependency!(manifest, root, opts)
        {native_root, native_bundles, {dependency, path}}
      else
        source =
          Path.expand(
            opts[:bundle_dir] || ".fow/#{manifest["environment"] || "default"}/bundles/apple",
            root
          )

        native = read_native_bundle!(source, "apple", manifest)
        {source, [{"apple", source, native}], nil}
      end

    {webview_dependency, webview_protected} = webview_path || {nil, nil}

    app = manifest["app"]["slug"] <> if(target == :mob, do: "_mobile", else: "_desktop")

    assigns = [
      app: app,
      module: Macro.camelize(app),
      name: manifest["app"]["name"],
      version: manifest["app"]["version"],
      name_json: Jason.encode!(manifest["app"]["name"]),
      origin: manifest["web"]["origin"],
      live: manifest["web"]["origin"] <> manifest["web"]["start_path"],
      live_json: Jason.encode!(manifest["web"]["origin"] <> manifest["web"]["start_path"]),
      width: get_in(manifest, ["elixirkit", "width"]) || 1060,
      height: get_in(manifest, ["elixirkit", "height"]) || 760,
      webview_dependency: webview_dependency,
      mobile_platforms: get_in(manifest, ["mob", "platforms"]) || ["android", "ios"],
      native_files:
        for(
          {_, _, native} <- native_bundles,
          {url, entry} <- Enum.sort(native["files"]),
          do: {Jason.encode!(url), Jason.encode!(entry["file"]), Jason.encode!(entry["mime"])}
        )
    ]

    Output.replace!(
      output,
      [force: opts[:force], protected: [root, bundle_path] ++ List.wrap(webview_protected)],
      fn stage ->
        if target == :mob do
          scaffold = opts[:scaffold] || (&scaffold_mob!/3)
          scaffold.(stage, app, manifest)

          for {platform, source, native} <- native_bundles,
              do:
                copy_native_bundle!(
                  source,
                  Path.join(stage, "priv/fog_of_war/#{platform}"),
                  native
                )
        else
          [{_, source, native}] = native_bundles
          copy_native_bundle!(source, Path.join(stage, "priv/fog_of_war/apple"), native)
        end

        Manifest.write!(Path.join(stage, ".fow.json"), manifest)
        put!(stage, "mix.exs", mixfile(target, assigns))

        if target == :mob,
          do: mobile!(stage, assigns, manifest),
          else: desktop!(stage, assigns, manifest)

        icon = manifest["app"]["icon"]

        if icon do
          Manifest.relative_path!(icon)
          Export.reject_symlinks!(root, icon)
          put!(stage, "branding/source" <> Path.extname(icon), File.read!(Path.join(root, icon)))
        end

        put!(
          stage,
          ".gitignore",
          "/deps/\n/_build/\n/src-tauri/target/\n/android/.gradle/\n/android/app/build/\n/mob.local.exs\n"
        )

        put!(stage, "README.md", readme(target, assigns))
      end
    )
  end

  defp webview_dependency!(manifest, root, opts) do
    source = get_in(manifest, ["mob", "webview"]) || %{}
    path = opts[:webview_path] || source["path"] || get_in(manifest, ["mob", "webview_path"])
    git = opts[:webview_git] || source["git"] || if(!path, do: @mob_webview_git)
    ref = opts[:webview_ref] || source["ref"] || if(git == @mob_webview_git, do: @mob_webview_ref)

    cond do
      path && git ->
        Mix.raise("Choose either a local WebView path or a Git dependency")

      is_binary(path) ->
        path = Path.expand(path, root)

        if !(File.regular?(Path.join(path, "priv/mob_plugin.exs")) &&
               File.regular?(Path.join(path, "mix.exs"))),
           do: Mix.raise("--webview-path must point to the MobWebView package")

        {"{:mob_webview, path: #{inspect(path)}}", path}

      is_binary(git) ->
        if !(is_binary(ref) && Regex.match?(~r/^[a-fA-F0-9]{40}$/, ref)),
          do: Mix.raise("--webview-git requires --webview-ref with a full pinned commit SHA")

        if !String.starts_with?(git, ["git@", "ssh://", "https://"]),
          do: Mix.raise("WebView Git source must be an SSH or HTTPS repository URL")

        {"{:mob_webview, git: #{inspect(git)}, ref: #{inspect(ref)}}", nil}

      true ->
        Mix.raise("MobWebView is not published yet; pass --webview-path or --webview-git with --webview-ref")
    end
  end

  defp read_native_bundles!(native_root, manifest) do
    for platform <- get_in(manifest, ["mob", "platforms"]) || ["android", "ios"] do
      source = Path.join(native_root, platform)

      if !File.regular?(Path.join(source, "native.json")),
        do:
          Mix.raise(
            "Prepare the #{platform} bundle first: mix fow.bundle.prepare --platform #{platform} (or pass --bundle-dir)"
          )

      {platform, source, read_native_bundle!(source, platform, manifest)}
    end
  end

  defp read_native_bundle!(source, platform, manifest) do
    native = source |> Path.join("native.json") |> File.read!() |> Jason.decode!()
    index = source |> Path.join("index.json") |> File.read!() |> Jason.decode!()

    if !(native["schema"] == 1 && native["platform"] == platform &&
           native["url"] == manifest["web"]["origin"] <> manifest["web"]["start_path"] &&
           index["scope"] == "public" && index["origin"] == manifest["web"]["origin"] &&
           index["environment"] == manifest["environment"] &&
           Enum.sort(Map.keys(index["pages"])) ==
             Enum.sort(Enum.uniq(manifest["public"]["paths"]))),
       do: Mix.raise("Native #{platform} bundle must match the selected environment, origin and public paths")

    native
  end

  defp copy_native_bundle!(source, target, native) do
    files = [
      "native.json",
      "index.json",
      native["startup"] | Enum.map(native["files"], fn {_, entry} -> entry["file"] end)
    ]

    for file <- Enum.uniq(files) do
      Manifest.relative_path!(file)
      Export.reject_symlinks!(source, file)
      put!(target, file, File.read!(Path.join(source, file)))
    end
  end

  defp scaffold_mob!(stage, app, manifest) do
    # Invoke upstream once, internally. Users never need to hand-edit the native scaffold.
    parent = Path.join(stage, "scaffold")
    File.mkdir_p!(parent)
    platforms = get_in(manifest, ["mob", "platforms"]) || ["android", "ios"]

    flags =
      case platforms do
        ["android"] -> ["--android"]
        ["ios"] -> ["--ios"]
        _ -> []
      end

    {log, status} =
      System.cmd(
        System.find_executable("mix"),
        ["mob.new", app, "--blank", "--no-install", "--dest", parent] ++ flags,
        cd: System.tmp_dir!(),
        stderr_to_stdout: true
      )

    if status != 0,
      do: Mix.raise("Install the upstream generator first: mix archive.install hex mob_new\n#{log}")

    for entry <- File.ls!(Path.join(parent, app)),
        do: File.rename!(Path.join([parent, app, entry]), Path.join(stage, entry))

    File.rm_rf!(parent)
  end

  defp mixfile(target, a) do
    # Mob's blank native scaffold links SQLite, so retain its source dependency.
    platform =
      if target == :mob,
        do:
          ~s|, #{a[:webview_dependency]}, {:mob, "== 0.9.27"}, {:ecto_sqlite3, "~> 0.18"}, {:mob_dev, "~> 0.7.31", only: :dev, runtime: false}|,
        else: ""

    erlang =
      if target == :mob, do: ", erlc_paths: [\"src\"], erlc_options: [:debug_info]", else: ""

    elixir_requirement = if target == :mob, do: "~> 1.19", else: "~> 1.18"

    """
    defmodule #{a[:module]}.MixProject do
      use Mix.Project
      def project, do: [app: :#{a[:app]}, version: "#{a[:version]}", elixir: "#{elixir_requirement}",
        start_permanent: Mix.env() == :prod,
        deps: [{:bandit, "~> 1.8"}, {:plug, "~> 1.18"}, {:jason, "~> 1.4"}#{platform}]#{erlang}]
      def application, do: [extra_applications: [:logger]]
    end
    """
  end

  defp mobile!(stage, a, manifest) do
    File.rm(Path.join(stage, "lib/#{a[:app]}/repo.ex"))
    File.rm_rf!(Path.join(stage, "test/#{a[:app]}"))
    put!(stage, "test/#{a[:app]}/home_screen_test.exs", template("mobile_test.exs.eex", a))
    put!(stage, "config/config.exs", "import Config\nconfig :mob, :plugins, [:mob_webview]\n")
    put!(stage, "lib/#{a[:app]}/app.ex", template("mobile_app.ex.eex", a))
    put!(stage, "lib/#{a[:app]}/home_screen.ex", template("mobile_screen.ex.eex", a))
    # The plugin owns native registration and asset serving; do not patch Mob's built-in WebView.
    File.rm(Path.join(stage, "prepare-native.exs"))
    gradle = Path.join(stage, "android/app/build.gradle")

    if File.exists?(gradle) do
      source = File.read!(gradle)

      source =
        Regex.replace(
          ~r/applicationId\s+"[^"]+"/,
          source,
          "applicationId \"#{manifest["app"]["identifier"]}\""
        )

      source =
        String.replace(
          source,
          "dependencies {",
          "dependencies {\n    implementation 'androidx.webkit:webkit:1.12.1'",
          global: false
        )

      source =
        Regex.replace(
          ~r/versionName\s+"[^\"]+"/,
          source,
          "versionName \"#{manifest["app"]["version"]}\""
        )

      File.write!(gradle, source)
    end

    # BSD cp's sparse-file optimization can zero the ELF header of an NDK-linked
    # library on macOS. Copy densely on the host; Linux cp has no -S option.
    zig = Path.join(stage, "android/app/src/main/jni/build.zig")

    if File.regular?(zig) do
      source = File.read!(zig)
      copy = ~s|const cp = b.addSystemCommand(&.{"cp"});|

      if length(:binary.matches(source, copy)) != 2,
        do: Mix.raise("Unexpected Mob Android library-copy steps; review the pinned scaffold")

      File.write!(
        zig,
        String.replace(
          source,
          copy,
          copy <> ~s{\n    if (@import("builtin").os.tag == .macos) cp.addArg("-S");}
        )
      )
    end

    android_manifest = Path.join(stage, "android/app/src/main/AndroidManifest.xml")

    if File.exists?(android_manifest) do
      source = File.read!(android_manifest)

      source =
        Regex.replace(~r/android:label="[^"]*"/, source, fn _ ->
          "android:label=\"#{xml(a[:name])}\""
        end)

      File.write!(android_manifest, source)
    end

    plist = Path.join(stage, "ios/Info.plist")

    if File.exists?(plist) do
      source = File.read!(plist)

      source =
        Regex.replace(
          ~r/<key>CFBundleIdentifier<\/key>\s*<string>[^<]*<\/string>/,
          source,
          "<key>CFBundleIdentifier</key><string>#{manifest["app"]["identifier"]}</string>"
        )

      # Leave executable/module naming to upstream; only set the user-facing display name.
      source =
        String.replace(
          source,
          "<dict>",
          "<dict>\n<key>CFBundleDisplayName</key><string>#{xml(a[:name])}</string>\n<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>",
          global: false
        )

      File.write!(plist, source)
    end

    # Upstream stamps these from mob.exs when building iOS.
    File.write!(
      Path.join(stage, "mob.exs"),
      "\nconfig :mob_dev, bundle_id: #{inspect(manifest["app"]["identifier"])}\n" <>
        "config :mob, :plugins, [:mob_webview]\n" <>
        "# Explicit local, inspected prototype dependency. Sign/trust the plugin for distribution.\n" <>
        "config :mob, :acknowledge_unsafe_plugins, [:mob_webview]\n",
      [:append]
    )

    put!(stage, "build.sh", """
    #!/usr/bin/env bash
    set -euo pipefail
    cd "$(dirname "$0")"
    mix deps.get
    mix mob.install
    mix mob.deploy --native "$@"
    """)

    File.chmod!(Path.join(stage, "build.sh"), 0o755)
  end

  defp desktop!(stage, a, manifest) do
    icon = File.read!(Application.app_dir(:fow, "priv/templates/wrapper/fallback.png"))
    put!(stage, "branding/fallback.png", icon)
    put!(stage, "src-tauri/icons/icon.png", icon)

    put!(stage, "src-tauri/src/main.rs", template("desktop_apple_main.rs.eex", a))
    put!(stage, "src-tauri/src/desktop_bundle.rs", template("desktop_bundle.rs.eex", a))

    build_script =
      """
      fn main() {
          let commands = tauri_build::AppManifest::new().commands(&["read_fow_bundle_asset"]);
          tauri_build::try_build(tauri_build::Attributes::new().app_manifest(commands))
              .expect("generate desktop capabilities");
      }
      """

    put!(stage, "src-tauri/build.rs", build_script)

    put!(stage, "src-tauri/Cargo.toml", """
    [package]
    name = "#{a[:app]}"
    version = "#{manifest["app"]["version"]}"
    edition = "2021"
    [build-dependencies]
    tauri-build = { version = "=2.7.4", features = [] }
    [dependencies]
    tauri = { version = "=2.12.5", features = [] }
    objc2 = "=0.6.5"\nobjc2-foundation = { version = "=0.3.2", default-features = false }\nobjc2-web-kit = { version = "=0.3.2", default-features = false, features = ["WKWebView", "WKNavigation"] }
    [features]
    custom-protocol = ["tauri/custom-protocol"]
    """)

    capabilities =
      [
        %{
          "identifier" => "fow-public-bundle",
          "local" => false,
          "remote" => %{"urls" => [a[:origin] <> "/*"]},
          "windows" => ["main"],
          "permissions" => ["allow-read-fow-bundle-asset"]
        }
      ]

    config = %{
      "$schema" => "https://schema.tauri.app/config/2",
      "productName" => a[:name],
      "version" => manifest["app"]["version"],
      "identifier" => manifest["app"]["identifier"],
      "app" => %{"windows" => [], "security" => %{"capabilities" => capabilities}},
      "bundle" => %{
        "active" => true,
        "targets" => ["app"],
        "resources" => %{},
        "macOS" => %{"minimumSystemVersion" => "12.0"},
        "icon" => ["icons/icon.icns", "icons/icon.png"]
      }
    }

    put!(stage, "src-tauri/tauri.conf.json", Jason.encode!(config, pretty: true))

    put!(stage, "src-tauri/App.entitlements", """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict><key>com.apple.security.cs.allow-jit</key><true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
    <key>com.apple.security.cs.disable-library-validation</key><true/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key><true/></dict></plist>
    """)

    put!(stage, "build.sh", """
    #!/usr/bin/env bash
    set -euo pipefail
    cd "$(dirname "$0")"
    if [ "$(uname -s)" != Darwin ]; then echo "This first release recipe requires macOS." >&2; exit 1; fi
    icons=(branding/source.*)
    if [ ! -f "${icons[0]}" ]; then icons=(branding/fallback.png); fi
    if [ -f "${CLIENT_TAURI_JS:-}" ]; then
      node "$CLIENT_TAURI_JS" icon "${icons[0]}" --fit contain --output src-tauri/icons
      node "$CLIENT_TAURI_JS" build --bundles app --ci
    else
      cargo tauri icon "${icons[0]}" --fit contain --output src-tauri/icons
      cargo tauri build --bundles app --ci
    fi
    bundle_name=#{shell_quote(a[:name] <> ".app")}
    codesign --force --deep --sign - "${CARGO_TARGET_DIR:-$PWD/src-tauri/target}/release/bundle/macos/$bundle_name"
    """)

    File.chmod!(Path.join(stage, "build.sh"), 0o755)
  end

  defp template(name, assigns),
    do: EEx.eval_file(Application.app_dir(:fow, "priv/templates/wrapper/#{name}"), assigns: assigns)

  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"

  defp xml(value),
    do:
      value
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")
      |> String.replace("\"", "&quot;")

  defp put!(root, path, content) do
    file = Path.join(root, path)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, content)
  end

  defp readme(:mob, a) do
    """
    # #{a[:name]} — Mob wrapper

    Generated source for a seamless native WebView wrapper around #{a[:origin]}. Each selected platform has its own prepared bundle in `priv/fog_of_war/<platform>`. The initial public HTML, application JavaScript, styles, images and gzip route records are bundled. FoW imports the records into IndexedDB and handles offline navigation; the real LiveView connection retries in the background. There is no native Live/Offline toolbar or Open live site button.

    Run `./build.sh --android` or `./build.sh --ios` with that platform's SDK and a selected device. Generation itself does not build native binaries. The MobWebView dependency in `mix.exs` records the explicitly supplied local checkout or pinned Git commit. The package is not published to Hex yet. Keep local checkouts available; private Git sources require repository access for each builder. The local prototype plugin is explicitly acknowledged in `mob.exs`; production distribution should sign and trust it. The server-side FoW package does not depend on MobWebView.

    `./build.sh` uses Mob's own install/deploy commands. No patch to Mob's built-in WebView is needed. On Android, a development URL using the Mac's loopback address requires `adb reverse tcp:PORT tcp:PORT` for online recovery. Offline startup does not require forwarding. Production URLs should be device-reachable HTTPS origins.

    Prepared bundles are immutable inputs to this generated source project. To update them, prepare each selected platform again, then regenerate with `--force`; that replaces the entire generated directory, so keep your own integrations in version control before regenerating. Commit dependency/native lockfiles after the first build. Only explicitly public routes are bundled; do not capture a logged-in session.

    Android ARM64 cold-offline startup and recovery have a device test in FoW. The Apple API has SDK compile checks only; iOS custom-scheme fetch, storage and canvas behavior still need runtime verification. Native launch icons remain Mob scaffold artwork until applying Mob's icon workflow to `branding/source.*`. Production signing, OAuth and store submission are separate steps.
    """
  end

  defp readme(:elixirkit, a) do
    """
    # #{a[:name]} — macOS WebKit wrapper

    Run `bash build.sh` on macOS with Rust, Tauri CLI, and Xcode command-line tools.
    Open `#{a[:name]}.app` in the Cargo target's `release/bundle/macos` directory.
    The app opens the embedded startup document at #{a[:live]} and reads the
    bundled public snapshots through a native command. Online navigation uses
    the configured website. Regenerate this project to refresh the embedded bundle.
    """
  end
end
