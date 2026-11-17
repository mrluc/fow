defmodule FogOfWar.CacheExportTest do
  use ExUnit.Case, async: false
  alias FogOfWar.Wrapper.{CacheExport, NativeBundle, Generator, Manifest}

  setup do
    root = Path.join(System.tmp_dir!(), "fow-cache-export-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    manifest = %{
      "schema" => 3,
      "default_env" => "dev",
      "envs" => %{
        "dev" => %{},
        "release-candidate" => %{
          "app" => %{"identifier" => "dev.example.candidate", "name" => "Candidate"},
          "web" => %{"origin" => "https://candidate.example"},
          "preload" => %{"paths" => []}
        }
      },
      "app" => %{
        "name" => "Example",
        "slug" => "example",
        "identifier" => "dev.example.app",
        "version" => "0.1.0"
      },
      "web" => %{"origin" => "https://example.com"},
      "startup" => %{"path" => "/"},
      "preload" => %{"paths" => ["/two"]},
      "assets" => %{"directories" => []},
      "mob" => %{"platforms" => ["android"]},
      "elixirkit" => %{"width" => 800, "height" => 600}
    }

    %{root: root, manifest: manifest}
  end

  defp html(url) do
    path = URI.parse(url).path

    ~s(<!doctype html><html><head><title>Public #{path}</title><script src="/assets/app.js"></script></head><body><main id="page" phx-hook="FogOfWar" data-fog-of-war-path="#{path}"><p>こんにちは 🌲 #{String.duplicate("public content ", 60)}</p><button phx-click="go">Go</button></main></body></html>)
  end

  test "environment maps merge recursively, lists replace, arbitrary names and identifiers resolve",
       %{manifest: doc} do
    dev = Manifest.resolve!(doc)
    assert dev["environment"] == "dev"
    assert dev["public"]["bundle"] == ".fow/dev/bundles/source"
    candidate = Manifest.resolve!(doc, "release-candidate")
    assert candidate["app"]["slug"] == "example"
    assert candidate["app"]["name"] == "Candidate"
    assert candidate["app"]["identifier"] == "dev.example.candidate"
    assert candidate["public"]["paths"] == ["/"]
    assert candidate["web"]["start_path"] == "/"
    assert candidate["public"]["bundle"] == ".fow/release-candidate/bundles/source"
    assert Manifest.resolve!(candidate) == candidate
  end

  test "validation happens after merging, including when defaults are incomplete", %{
    manifest: doc
  } do
    app = doc["app"]
    partial = doc |> Map.delete("app") |> put_in(["envs", "dev", "app"], app)
    assert Manifest.resolve!(partial)["app"] == app
    assert_raise Mix.Error, fn -> Manifest.resolve!(partial, "release-candidate") end
    assert_raise Mix.Error, ~r/Unknown/, fn -> Manifest.resolve!(doc, "typo") end

    assert_raise Mix.Error, fn ->
      Manifest.resolve!(put_in(doc, ["envs", "dev", "web"], %{"origin" => nil}))
    end

    assert_raise Mix.Error, fn ->
      Manifest.resolve!(put_in(doc, ["envs", "dev", "preload"], %{"paths" => ["/../bad"]}))
    end
  end

  test "old schemas are rejected", %{manifest: doc} do
    for schema <- [1, 2],
        do: assert_raise(Mix.Error, fn -> Manifest.resolve!(Map.put(doc, "schema", schema)) end)
  end

  test "binary export is decodable, indexed by path, debug-friendly and contains complete startup HTML",
       %{manifest: doc, root: root} do
    manifest = Manifest.resolve!(doc)
    output = Path.join(root, "cache")
    index = CacheExport.run!(manifest, output, fetch: &html/1, debug: true)
    assert index["environment"] == "dev"
    assert map_size(index["pages"]) == 2
    refute Jason.encode!(index) =~ "htmlGzip"

    for {path, record} <- index["pages"] do
      gzip = File.read!(Path.join(output, record["file"]))
      assert byte_size(gzip) == record["compressedBytes"]
      region = :zlib.gunzip(gzip)
      assert region =~ "こんにちは 🌲"
      assert region =~ ~s(data-fog-of-war-path="#{path}")
      assert byte_size(region) == record["htmlBytes"]
      assert record["compressedBytes"] < record["htmlBytes"]
      assert record["sha256"] == Base.encode16(:crypto.hash(:sha256, gzip), case: :lower)
    end

    assert File.read!(Path.join(output, "startup.html")) == html("https://example.com/")
    assert length(Path.wildcard(Path.join(output, "debug/*/response.html"))) == 2
    assert Jason.decode!(File.read!(Path.join(output, "index.json"))) == index
  end

  test "wrong region identity or missing marker fails visibly without publishing a partial bundle",
       %{manifest: doc, root: root} do
    manifest = Manifest.resolve!(doc)

    for {name, fetch} <- [
          {"missing", fn _ -> "<html><body>oops</body></html>" end},
          {"wrong", fn _ -> html("https://example.com/wrong") end},
          {"duplicate", fn url -> html(url) <> html(url) end}
        ] do
      output = Path.join(root, name)
      assert_raise Mix.Error, fn -> CacheExport.run!(manifest, output, fetch: fetch) end
      refute File.exists?(output)
      assert Path.wildcard(output <> ".tmp-*") == []
    end
  end

  test "capture address can differ from the app origin without relabeling cached routes", %{
    manifest: doc,
    root: root
  } do
    manifest =
      doc |> Map.put("capture", %{"origin" => "http://127.0.0.1:47180"}) |> Manifest.resolve!()

    index =
      CacheExport.run!(manifest, Path.join(root, "capture"),
        fetch: fn url ->
          assert String.starts_with?(url, "http://127.0.0.1:47180/")
          html(url)
        end
      )

    assert index["origin"] == "https://example.com"
    assert index["capture_origin"] == "http://127.0.0.1:47180"
  end

  test "Apple bundle includes cache files and desktop generation copies them with resolved identity",
       %{manifest: doc, root: root} do
    Manifest.write!(Path.join(root, ".fow.json"), doc)
    manifest = Manifest.resolve!(doc, "release-candidate")
    source = Path.join(root, ".fow/release-candidate/bundles/apple")

    bundle =
      NativeBundle.run!(manifest, root, source, "apple",
        fetch: fn url ->
          String.replace(html(url), ~s(<script src="/assets/app.js"></script>), "")
        end
      )

    Generator.run!(:elixirkit, Path.join(root, ".fow.json"), Path.join(root, "desktop"),
      env: "release-candidate"
    )

    for {_url, %{"file" => file}} <- bundle["files"] do
      assert File.read!(Path.join([root, "desktop/priv/fog_of_war/apple", file])) ==
               File.read!(Path.join(source, file))
    end

    resolved = Manifest.read!(Path.join(root, "desktop/.fow.json"))
    assert resolved["app"]["identifier"] == "dev.example.candidate"
    assert resolved["environment"] == "release-candidate"

    tauri =
      Path.join(root, "desktop/src-tauri/tauri.conf.json") |> File.read!() |> Jason.decode!()

    assert tauri["identifier"] == "dev.example.candidate"
    # Even equal origins must not let a generator consume another environment's bundle.
    bundle_file = Path.join(source, "index.json")

    File.write!(
      bundle_file,
      Jason.encode!(Map.put(Jason.decode!(File.read!(bundle_file)), "environment", "dev"))
    )

    assert_raise Mix.Error, ~r/selected environment/, fn ->
      Generator.run!(
        :elixirkit,
        Path.join(root, ".fow.json"),
        Path.join(root, "wrong-environment"),
        env: "release-candidate"
      )
    end
  end
end
