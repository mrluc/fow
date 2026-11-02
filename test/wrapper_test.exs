defmodule FogOfWar.WrapperTest do
  use ExUnit.Case, async: false
  alias FogOfWar.Wrapper.{Export, Generator, Manifest}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "fog-of-war-wrapper-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "priv/static/css"))
    File.write!(Path.join(root, "priv/static/css/site.css"), "body { color: green }")

    manifest = %{
      "schema" => 1,
      "app" => %{
        "name" => "Sample",
        "slug" => "sample",
        "identifier" => "dev.example.sample",
        "version" => "0.1.0"
      },
      "web" => %{"origin" => "https://example.com", "start_path" => "/"},
      "public" => %{
        "paths" => ["/", "/two"],
        "static_root" => "priv/static",
        "bundle" => "public",
        "asset_directories" => ["css"]
      },
      "mob" => %{"platforms" => ["android", "ios"]},
      "elixirkit" => %{"width" => 800, "height" => 600}
    }

    html = """
    <html><head><title>Sample</title><meta name="csrf-token" content="SECRET"><link rel="canonical" href="https://example.com/"><link rel="stylesheet" href="/css/site.css"><script>secret()</script></head>
    <body><div data-phx-session="SIGNED"><main id="site" phx-hook="FogOfWar" data-fog-of-war-path="/">
    <a href="/two" data-phx-link="redirect">Two</a><button phx-click="increment">Increment</button>
    <input type="hidden" value="SECRET"><input type="password" value="SECRET">
    </main><aside phx-hook="FogOfWarDevTools">dev tools</aside></div></body></html>
    """

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, manifest: manifest, html: html}
  end

  test "export strips executable and session state, keeps navigation and copies only public assets",
       context do
    %{root: root, manifest: manifest, html: html} = context
    bundle = Export.run!(manifest, root, Path.join(root, "public"), fetch: fn _ -> html end)
    assert map_size(bundle["pages"]) == 2
    assert bundle["assets"] == %{"/css/site.css" => "assets/css/site.css"}
    page = File.read!(Path.join([root, "public", bundle["pages"]["/"]["file"]]))
    refute page =~ "SECRET"
    refute page =~ "SIGNED"
    refute page =~ "secret()"
    refute page =~ "dev tools"
    refute page =~ "data-phx-session"
    assert page =~ "href=\"/two\""
    assert page =~ "disabled=\"disabled\""
    assert page =~ "connect-src 'none'"
    assert page =~ "src=\"/_fog/bootstrap.js\""

    assert_raise Mix.Error, ~r/destination exists/, fn ->
      Export.run!(manifest, root, Path.join(root, "public"))
    end
  end

  test "a generated desktop contains public artifacts and standalone code, never source Phoenix app",
       %{root: root, manifest: manifest, html: html} do
    Export.run!(manifest, root, Path.join(root, "public"), fetch: fn _ -> html end)
    Manifest.write!(Path.join(root, ".fow.json"), manifest)
    output = Path.join(root, "desktop")
    Generator.run!(:elixirkit, Path.join(root, ".fow.json"), output)
    mix = File.read!(Path.join(output, "mix.exs"))
    refute mix =~ ":phoenix"
    refute mix =~ ":fow"
    refute mix =~ "path:"
    assert mix =~ ":elixirkit"

    for file <- Path.wildcard(Path.join(output, "lib/**/*.ex")) ++ [Path.join(output, "mix.exs")],
        do: Code.string_to_quoted!(File.read!(file))

    assert File.read!(Path.join(output, "src-tauri/src/main.rs")) =~ ".initialization_script"

    assert_raise Mix.Error, ~r/Destination exists/, fn ->
      Generator.run!(:elixirkit, Path.join(root, ".fow.json"), output)
    end
  end

  test "public assets cannot follow symlinks outside static root", %{
    root: root,
    manifest: manifest,
    html: html
  } do
    File.write!(Path.join(root, "secret.css"), "not public")
    File.rm!(Path.join(root, "priv/static/css/site.css"))
    File.ln_s!(Path.join(root, "secret.css"), Path.join(root, "priv/static/css/site.css"))

    assert_raise Mix.Error, ~r/symlinked/, fn ->
      Export.run!(manifest, root, Path.join(root, "public"), fetch: fn _ -> html end)
    end

    refute File.exists?(Path.join(root, "public"))
  end

  test "manifest requires explicit public paths and rejects ambiguous origins or escaping paths",
       %{manifest: manifest, root: root} do
    assert Manifest.validate!(manifest) == manifest

    for path <- ["//outside.test", "/../secret", "/%2e%2e/secret", "/route?token=secret"] do
      assert_raise Mix.Error, fn -> Manifest.validate_path!(path) end
    end

    assert_raise Mix.Error, fn ->
      Manifest.validate!(put_in(manifest, ["web", "origin"], "https://example.com/app"))
    end

    assert_raise Mix.Error, fn ->
      Export.run!(put_in(manifest, ["public", "paths"], []), root, Path.join(root, "public"))
    end
  end

  test "mobile document-start patches refresh and apply twice without accumulating code", %{
    root: root
  } do
    android = Path.join(root, "android/app/src/main/java/example/MobBridge.kt")
    ios = Path.join(root, "deps/mob/ios/MobRootView.swift")
    File.mkdir_p!(Path.dirname(android))
    File.mkdir_p!(Path.dirname(ios))
    File.mkdir_p!(Path.join(root, "ios"))
    File.mkdir_p!(Path.join(root, "priv"))
    File.write!(android, "// WebView factory\n                loadUrl(url)\n")
    File.write!(ios, "        let wv = WKWebView(frame: .zero, configuration: config)\n")
    seed = Path.join(root, "priv/fog_of_war_seed.js")
    File.write!(seed, String.duplicate("/* public */", 7_000))

    script =
      EEx.eval_file(Application.app_dir(:fow, "priv/templates/wrapper/prepare_mobile.exs.eex"),
        assigns: [origin: "https://example.com"]
      )

    File.write!(Path.join(root, "prepare-native.exs"), script)

    run = fn ->
      System.cmd(System.find_executable("elixir"), ["prepare-native.exs"],
        cd: root,
        stderr_to_stdout: true
      )
    end

    assert {_, 0} = run.()
    first = File.read!(android)
    assert first =~ "listOf("
    assert {_, 0} = run.()
    assert File.read!(android) == first
    File.write!(seed, "/* newer public bundle */")
    assert {_, 0} = run.()
    refute File.read!(android) == first
    assert length(:binary.matches(File.read!(android), "FOG_OF_WAR_DOCUMENT_START")) == 1
    File.write!(android, "// changed upstream layout")
    assert {log, status} = run.()
    assert status != 0
    assert log =~ "anchor changed"
  end
end
