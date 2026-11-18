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
    index = root |> Path.join("index.json") |> File.read!() |> Jason.decode!()

    for {_, record} <- index["pages"] do
      bytes = File.read!(Path.join(root, record["file"]))
      assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == record["sha256"]
    end
  end

  test "iOS inlines startup code, rewrites image URLs and preserves live navigation",
       ctx do
    root = Path.join(ctx.root, "ios")
    native = NativeBundle.run!(ctx.manifest, ctx.root, root, "ios", fetch: ctx.fetch)
    assert native["url"] == "https://example.com/"
    assert native["files"]["fog-of-war-assets://bundle/assets/tree.png"]
    html = File.read!(Path.join(root, "startup.html"))
    assert html =~ "window.applicationRuns = true"
    assert html =~ "window.__fogOfWarNativeBundle="
    assert html =~ "<style>.ground{color:green}"
    assert html =~ "background:url('fog-of-war-assets://bundle/assets/tree.png')"
    refute html =~ ~r/<script\b[^>]*\bsrc=/
    refute html =~ ~s(rel="stylesheet")
    refute File.exists?(Path.join(root, "boot.js"))
    assert html =~ ~s(href="/two")
    css = File.read!(Path.join(root, "assets/assets/app.css"))
    assert css =~ "fog-of-war-assets://bundle/assets/terrain.css"
    assert css =~ "fog-of-war-assets://bundle/assets/tree.png"
    index = root |> Path.join("index.json") |> File.read!() |> Jason.decode!()
    assert index["origin"] == "https://example.com"
    record = index["pages"]["/two"]
    bytes = File.read!(Path.join(root, record["file"]))
    assert byte_size(bytes) == record["compressedBytes"]
    assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == record["sha256"]
    assert :zlib.gunzip(bytes) =~ "fog-of-war-assets://bundle/assets/tree.png"
  end

  test "Apple target matches the existing iOS scheme, startup, assets and gzip payloads", ctx do
    ios_root = Path.join(ctx.root, "ios")
    apple_root = Path.join(ctx.root, "apple")
    ios = NativeBundle.run!(ctx.manifest, ctx.root, ios_root, "ios", fetch: ctx.fetch)
    apple = NativeBundle.run!(ctx.manifest, ctx.root, apple_root, "apple", fetch: ctx.fetch)

    assert ios["platform"] == "ios"
    assert apple["platform"] == "apple"
    assert apple["url"] == "https://example.com/"
    assert ios["url"] == apple["url"]
    assert Enum.sort(Map.keys(apple["files"])) == Enum.sort(Map.keys(ios["files"]))

    assert File.read!(Path.join(apple_root, "startup.html")) ==
             File.read!(Path.join(ios_root, "startup.html"))

    for file <- ["assets/assets/app.css", "assets/assets/terrain.css"] do
      assert File.read!(Path.join(apple_root, file)) == File.read!(Path.join(ios_root, file))
    end

    apple_index = apple_root |> Path.join("index.json") |> File.read!() |> Jason.decode!()
    ios_index = ios_root |> Path.join("index.json") |> File.read!() |> Jason.decode!()
    assert apple_index["origin"] == "https://example.com"
    assert apple_index["origin"] == ios_index["origin"]

    assert Enum.sort(Map.keys(apple_index["pages"])) ==
             Enum.sort(Map.keys(ios_index["pages"]))

    for {path, apple_record} <- apple_index["pages"] do
      ios_record = ios_index["pages"][path]
      apple_bytes = File.read!(Path.join(apple_root, apple_record["file"]))
      ios_bytes = File.read!(Path.join(ios_root, ios_record["file"]))
      apple_html = :zlib.gunzip(apple_bytes)
      ios_html = :zlib.gunzip(ios_bytes)

      assert apple_html == ios_html
      assert apple_html =~ "fog-of-war-assets://bundle/assets/tree.png"
      assert apple_html =~ ~s(href="/two")
      assert byte_size(apple_bytes) == apple_record["compressedBytes"]

      assert Base.encode16(:crypto.hash(:sha256, apple_bytes), case: :lower) ==
               apple_record["sha256"]
    end
  end
end
