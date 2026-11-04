defmodule FogOfWar.NativeBundleTest do
  use ExUnit.Case, async: true
  alias FogOfWar.Wrapper.NativeBundle

  setup do
    root = Path.join(System.tmp_dir!(), "fog-native-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "priv/static/assets"))
    File.write!(Path.join(root, "priv/static/assets/app.js"), "window.applicationRuns = true")

    File.write!(
      Path.join(root, "priv/static/assets/app.css"),
      "@import url('./terrain.css'); .tree{background:url('./tree.png')}"
    )

    File.write!(Path.join(root, "priv/static/assets/terrain.css"), ".ground{color:green}")
    File.write!(Path.join(root, "priv/static/assets/tree.png"), "png-bytes")
    on_exit(fn -> File.rm_rf!(root) end)

    manifest = %{
      "environment" => "dev",
      "web" => %{"origin" => "https://example.com", "start_path" => "/"},
      "public" => %{
        "paths" => ["/", "/two"],
        "static_root" => "priv/static",
        "asset_directories" => ["assets"]
      }
    }

    fetch = fn url ->
      path = URI.parse(url).path

      ~s(<html><head data-phx-loc="1"><script defer src="/assets/app.js"></script><link rel="stylesheet" href="/assets/app.css"></head><body><!-- LiveView annotation --><div data-phx-main data-phx-session="kept"><main id="page" phx-hook="FogOfWar" data-fog-of-war-path="#{path}"><img src="/assets/tree.png"><a href="/two" data-phx-link="redirect">Two</a></main></div></body></html>)
    end

    %{root: root, manifest: manifest, fetch: fetch}
  end

  test "Android keeps executable LiveView startup and bundles scripts and recursive CSS resources",
       ctx do
    root = Path.join(ctx.root, "android")
    native = NativeBundle.run!(ctx.manifest, ctx.root, root, "android", fetch: ctx.fetch)
    assert map_size(native["files"]) == 8
    assert native["files"]["https://example.com/assets/app.js"]["mime"] =~ "javascript"
    html = File.read!(Path.join(root, "startup.html"))
    assert html =~ "data-phx-session=\"kept\""
    assert html =~ "https://example.com/assets/app.js"
    assert html =~ "__fog_of_war_bundle/boot.js"
    refute html =~ "Open live site"
    index = File.read!(Path.join(root, "index.json")) |> Jason.decode!()

    for {_, record} <- index["pages"] do
      bytes = File.read!(Path.join(root, record["file"]))
      assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == record["sha256"]
    end
  end

  test "iOS rewrites only asset URLs, including CSS and compressed records; origin and navigation remain real",
       ctx do
    root = Path.join(ctx.root, "ios")
    native = NativeBundle.run!(ctx.manifest, ctx.root, root, "ios", fetch: ctx.fetch)
    assert native["url"] == "https://example.com/"
    assert native["files"]["fog-of-war-assets://bundle/assets/tree.png"]
    html = File.read!(Path.join(root, "startup.html"))
    assert html =~ "fog-of-war-assets://bundle/assets/app.js"
    assert html =~ ~s(href="/two")
    css = File.read!(Path.join(root, "assets/assets/app.css"))
    assert css =~ "fog-of-war-assets://bundle/assets/terrain.css"
    assert css =~ "fog-of-war-assets://bundle/assets/tree.png"
    index = File.read!(Path.join(root, "index.json")) |> Jason.decode!()
    assert index["origin"] == "https://example.com"
    record = index["pages"]["/two"]
    bytes = File.read!(Path.join(root, record["file"]))
    assert byte_size(bytes) == record["compressedBytes"]
    assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == record["sha256"]
    assert :zlib.gunzip(bytes) =~ "fog-of-war-assets://bundle/assets/tree.png"
  end
end
