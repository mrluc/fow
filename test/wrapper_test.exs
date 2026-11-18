defmodule FogOfWar.WrapperTest do
  use ExUnit.Case, async: false

  alias FogOfWar.Wrapper.Manifest
  alias FogOfWar.Wrapper.NativeBundle

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "fog-of-war-wrapper-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "priv/static/css"))
    File.write!(Path.join(root, "priv/static/css/site.css"), "body { color: green }")

    manifest = %{
      "schema" => 3,
      "app" => %{
        "name" => "Sample",
        "slug" => "sample",
        "identifier" => "dev.example.sample",
        "version" => "0.1.0"
      },
      "web" => %{"origin" => "https://example.com"},
      "startup" => %{"path" => "/"},
      "preload" => %{"paths" => ["/two"]},
      "assets" => %{"directories" => ["css"]},
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
    %{root: root, manifest: Manifest.resolve!(manifest), html: html}
  end

  test "CSS imports using url() and quoted paths are exported recursively", context do
    %{root: root, manifest: manifest, html: html} = context

    File.write!(
      Path.join(root, "priv/static/css/site.css"),
      "@import url('/css/terrain.css'); @import \"detail.css\";"
    )

    for name <- ["terrain.css", "detail.css"],
        do: File.write!(Path.join(root, "priv/static/css/" <> name), "body {color: green}")

    bundle =
      NativeBundle.run!(manifest, root, Path.join(root, manifest["public"]["bundle"]), "apple",
        fetch: fn url -> for_path(html, url) end
      )

    assert Map.has_key?(bundle["files"], "fog-of-war-assets://bundle/css/terrain.css")
    assert Map.has_key?(bundle["files"], "fog-of-war-assets://bundle/css/detail.css")
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
      NativeBundle.run!(manifest, root, Path.join(root, manifest["public"]["bundle"]), "apple",
        fetch: fn url -> for_path(html, url) end
      )
    end

    refute File.exists?(Path.join(root, manifest["public"]["bundle"]))
  end

  test "public assets cannot follow a symlink above the configured static directory", %{
    root: root,
    manifest: manifest,
    html: html
  } do
    File.rename!(Path.join(root, "priv"), Path.join(root, "other"))
    File.ln_s!(Path.join(root, "other"), Path.join(root, "priv"))
    output = Path.join(root, manifest["public"]["bundle"])

    assert_raise Mix.Error, ~r/symlinked/, fn ->
      NativeBundle.run!(manifest, root, output, "apple", fetch: fn url -> for_path(html, url) end)
    end

    refute File.exists?(output)
  end

  test "environment names are checked before being used as output directories", %{manifest: manifest} do
    assert Manifest.resolve!(Map.put(manifest, "environment", "android-dev"))["public"]["bundle"] ==
             ".fow/android-dev/bundles/source"

    assert_raise Mix.Error, ~r/Environment names/, fn ->
      Manifest.resolve!(Map.put(manifest, "environment", "../android"))
    end

    assert_raise Mix.Error, ~r/Environment names/, fn ->
      manifest |> Map.put("envs", %{"../android" => %{}}) |> Manifest.resolve!("../android")
    end
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
      NativeBundle.run!(
        put_in(manifest, ["public", "paths"], []),
        root,
        Path.join(root, manifest["public"]["bundle"]),
        "apple"
      )
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

  defp for_path(html, url) do
    String.replace(
      html,
      ~s(data-fog-of-war-path="/"),
      ~s(data-fog-of-war-path="#{URI.parse(url).path}")
    )
  end
end
