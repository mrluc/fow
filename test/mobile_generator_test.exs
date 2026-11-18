defmodule FogOfWar.MobileGeneratorTest do
  use ExUnit.Case, async: true

  alias FogOfWar.Wrapper.Generator
  alias FogOfWar.Wrapper.Manifest
  alias FogOfWar.Wrapper.NativeBundle

  setup do
    root =
      Path.join(System.tmp_dir!(), "fog-mobile-generator-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    manifest = %{
      "schema" => 3,
      "default_env" => "dev",
      "envs" => %{"dev" => %{}},
      "app" => %{
        "name" => "Frontier",
        "slug" => "frontier",
        "identifier" => "dev.test.frontier",
        "version" => "0.1.0"
      },
      "web" => %{"origin" => "https://frontier.example"},
      "startup" => %{"path" => "/"},
      "preload" => %{"paths" => []},
      "assets" => %{"directories" => []},
      "mob" => %{"platforms" => ["android", "ios"]}
    }

    path = Path.join(root, ".fow.json")
    Manifest.write!(path, manifest)
    resolved = Manifest.resolve!(manifest)
    native_root = Path.join(root, ".fow/dev/bundles")

    for platform <- ["android", "ios"] do
      NativeBundle.run!(resolved, root, Path.join(native_root, platform), platform,
        fetch: fn _ ->
          ~s(<html><head></head><body><main phx-hook="FogOfWar" id="map" data-fog-of-war-path="/">Map</main></body></html>)
        end
      )
    end

    webview = Path.join(root, "mob_webview")
    File.mkdir_p!(Path.join(webview, "priv"))
    File.write!(Path.join(webview, "mix.exs"), "# explicit local fixture")
    File.write!(Path.join(webview, "priv/mob_plugin.exs"), "%{name: :mob_webview}")
    scaffold = fn stage, _, _ -> File.write!(Path.join(stage, "mob.exs"), "import Config\n") end
    %{root: root, path: path, native_root: native_root, webview: webview, scaffold: scaffold}
  end

  test "native library copies are dense on macOS and unknown scaffold copies fail safely", ctx do
    for count <- [2, 1] do
      scaffold = fn stage, app, manifest ->
        ctx.scaffold.(stage, app, manifest)
        file = Path.join(stage, "android/app/src/main/jni/build.zig")
        File.mkdir_p!(Path.dirname(file))

        File.write!(
          file,
          String.duplicate(~s|const cp = b.addSystemCommand(&.{"cp"});| <> "\n", count)
        )
      end

      output = Path.join(ctx.root, "copies-#{count}")

      if count == 2 do
        Generator.run!(:mob, ctx.path, output, scaffold: scaffold)
        source = File.read!(Path.join(output, "android/app/src/main/jni/build.zig"))

        assert length(
                 :binary.matches(
                   source,
                   ~s|if (@import("builtin").os.tag == .macos) cp.addArg("-S");|
                 )
               ) == 2
      else
        assert_raise Mix.Error, ~r/Unexpected Mob Android library-copy steps/, fn ->
          Generator.run!(:mob, ctx.path, output, scaffold: scaffold)
        end

        refute File.exists?(output)
      end
    end
  end

  test "mobile generation consumes separate native bundles, uses plugin and has no legacy wrapper controls",
       ctx do
    output = Path.join(ctx.root, "generated")
    File.write!(Path.join(ctx.native_root, "android/not-declared.txt"), "not copied")
    Generator.run!(:mob, ctx.path, output, webview_path: ctx.webview, scaffold: ctx.scaffold)

    for platform <- ["android", "ios"] do
      source = Path.join(ctx.native_root, platform)
      native = source |> Path.join("native.json") |> File.read!() |> Jason.decode!()

      for file <- [
            "native.json",
            "index.json",
            native["startup"] | Enum.map(native["files"], fn {_, entry} -> entry["file"] end)
          ] do
        assert File.read!(Path.join([output, "priv/fog_of_war", platform, file])) ==
                 File.read!(Path.join(source, file))
      end
    end

    refute File.exists?(Path.join(output, "priv/fog_of_war/android/not-declared.txt"))
    refute File.exists?(Path.join(output, "priv/fog_of_war_seed.js"))
    refute File.exists?(Path.join(output, "lib/frontier_mobile/public_shell.ex"))
    refute File.exists?(Path.join(output, "prepare-native.exs"))
    screen = File.read!(Path.join(output, "lib/frontier_mobile/home_screen.ex"))
    assert screen =~ "MobWebView.view"
    assert screen =~ "socket.__mob__.platform"
    refute screen =~ "<Button"
    refute screen =~ "PublicShell"
    mix = File.read!(Path.join(output, "mix.exs"))
    assert mix =~ "{:mob_webview, path: #{inspect(ctx.webview)}}"
    assert mix =~ "ecto_sqlite3"
    assert File.read!(Path.join(output, "mob.exs")) =~ "plugins, [:mob_webview]"
    refute File.read!(Path.join(output, "build.sh")) =~ "prepare-native"

    for file <-
          Path.wildcard(Path.join(output, "**/*.ex")) ++
            Path.wildcard(Path.join(output, "**/*.exs")) do
      assert {:ok, _} = Code.string_to_quoted(File.read!(file)), file
    end
  end

  test "default dependency pins the dedicated Mob WebView repository", ctx do
    output = Path.join(ctx.root, "default-generated")
    Generator.run!(:mob, ctx.path, output, scaffold: ctx.scaffold)
    mix = File.read!(Path.join(output, "mix.exs"))
    assert mix =~ ~s(git: "https://github.com/mrluc/fow_webview_mob.git")
    assert mix =~ ~s(ref: "1be07da3604a64bc6ef11c87858c3c9ad372e80b")
  end

  test "explicit pinned Git dependency is recorded and no unpublished Hex version is assumed",
       ctx do
    output = Path.join(ctx.root, "git-generated")
    ref = String.duplicate("a", 40)

    Generator.run!(:mob, ctx.path, output,
      webview_git: "git@github.com:owner/webview.git",
      webview_ref: ref,
      scaffold: ctx.scaffold
    )

    assert File.read!(Path.join(output, "mix.exs")) =~
             ~s({:mob_webview, git: "git@github.com:owner/webview.git", ref: "#{ref}"})

    assert_raise Mix.Error, ~r/pinned commit/, fn ->
      Generator.run!(:mob, ctx.path, output <> "-bad",
        webview_git: "git@github.com:owner/webview.git",
        webview_ref: "main",
        scaffold: ctx.scaffold
      )
    end
  end

  test "environment mismatches and escaping native bundle files fail before replacement", ctx do
    output = Path.join(ctx.root, "generated")
    opts = [webview_path: ctx.webview, scaffold: ctx.scaffold]
    Generator.run!(:mob, ctx.path, output, opts)
    File.write!(Path.join(output, "keep.txt"), "old project")

    assert_raise Mix.Error, ~r/Destination exists/, fn ->
      Generator.run!(:mob, ctx.path, output, opts)
    end

    index_file = Path.join(ctx.native_root, "ios/index.json")
    original = File.read!(index_file)

    File.write!(
      index_file,
      original |> Jason.decode!() |> Map.put("environment", "prod") |> Jason.encode!()
    )

    assert_raise Mix.Error, ~r/selected environment/, fn ->
      Generator.run!(:mob, ctx.path, output, Keyword.put(opts, :force, true))
    end

    assert File.read!(Path.join(output, "keep.txt")) == "old project"
    File.write!(index_file, original)
    native_file = Path.join(ctx.native_root, "android/native.json")
    native = native_file |> File.read!() |> Jason.decode!()
    File.write!(native_file, native |> Map.put("startup", "../secret") |> Jason.encode!())

    assert_raise Mix.Error, ~r/project-relative/, fn ->
      Generator.run!(:mob, ctx.path, output, Keyword.put(opts, :force, true))
    end

    assert File.read!(Path.join(output, "keep.txt")) == "old project"
    File.write!(native_file, Jason.encode!(native))
    Generator.run!(:mob, ctx.path, output, Keyword.put(opts, :force, true))
    refute File.exists?(Path.join(output, "keep.txt"))
  end
end
