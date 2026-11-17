defmodule FogOfWar.Wrapper.CacheExport do
  @moduledoc """
  Fetches anonymous server-rendered pages and extracts their FoW regions for offline navigation. The result is a route index and gzip payloads that FoW can import into browser storage.

  ## How it fits

  Called directly by `FogOfWar.Wrapper.NativeBundle`. `mix fow.export.cache` exposes it as a separate capture step.
  """
  alias FogOfWar.Wrapper.{Export, Manifest}
  @build "fog-of-war-2"

  @doc "Capture every selected route into a fresh output directory and return the index."
  def run!(manifest, output, opts \\ []) do
    paths = paths!(manifest)
    if File.exists?(output), do: Mix.raise("Export destination exists: #{output}")
    stage = output <> ".tmp-#{System.unique_integer([:positive])}"
    File.mkdir_p!(stage)
    origin = capture_origin!(manifest, opts)
    fetch = opts[:fetch] || (&Export.fetch_html!/1)

    try do
      pages =
        Map.new(paths, fn path ->
          # Only this response and region are retained; the index contains metadata, not HTML.
          body = fetch.(origin <> path)
          {path, capture!(manifest, path, body, stage, Keyword.put(opts, :base_url, origin))}
        end)

      index = finish!(manifest, pages, stage, opts)
      File.mkdir_p!(Path.dirname(output))
      File.rename!(stage, output)
      index
    after
      File.rm_rf(stage)
    end
  end

  @doc "Return the distinct public routes to capture, including the startup route."
  def paths!(manifest) do
    paths = Enum.uniq(manifest["public"]["paths"])
    if paths == [], do: Mix.raise("Set public.paths explicitly before export")

    unless manifest["web"]["start_path"] in paths,
      do: Mix.raise("web.start_path must be one of public.paths")

    paths
  end

  @doc "Resolve the HTTP origin to fetch, honoring the explicit capture override."
  def capture_origin!(manifest, opts) do
    Manifest.validate_origin!(
      opts[:base_url] || get_in(manifest, ["capture", "origin"]) || manifest["web"]["origin"],
      "capture origin"
    )
  end

  @doc "Extract one FoW region from a rendered response and write its gzip record. Preserve the full document for the startup route."
  def capture!(manifest, path, body, root, opts \\ []) do
    document = Floki.parse_document!(body)

    region =
      case Floki.find(document, "[phx-hook=FogOfWar]") do
        [node] ->
          node

        nodes ->
          Mix.raise("#{path}: expected exactly one FogOfWar region, found #{length(nodes)}")
      end

    attrs = region |> elem(1) |> Map.new()

    if attrs["data-fog-of-war-user-id"] || attrs["data-fog-of-war-require-user-id"] == "true",
      do: Mix.raise("#{path}: cannot export an account-scoped FogOfWar region")

    if attrs["data-fog-of-war-path"] && attrs["data-fog-of-war-path"] != path,
      do: Mix.raise("#{path}: FogOfWar region declares #{inspect(attrs["data-fog-of-war-path"])}")

    html = Floki.raw_html([region])
    gzip = :zlib.gzip(html)
    name = :crypto.hash(:sha256, path) |> Base.encode16(case: :lower)
    file = "pages/#{name}.html.gz"
    write!(root, file, gzip)
    if path == manifest["web"]["start_path"], do: write!(root, "startup.html", body)

    if opts[:debug] do
      debug = "debug/#{name}"

      write!(
        root,
        debug <> "/request.json",
        Jason.encode!(%{method: "GET", url: capture_origin!(manifest, opts) <> path},
          pretty: true
        )
      )

      write!(root, debug <> "/response.html", body)
      write!(root, debug <> "/region.html", html)
    end

    saved_at = DateTime.utc_now()

    %{
      "schema" => 1,
      "build" => @build,
      "path" => path,
      "regionId" => attrs["id"],
      "title" => document |> Floki.find("title") |> Floki.text(),
      "savedAt" => DateTime.to_iso8601(saved_at),
      "file" => file,
      "encoding" => "gzip",
      "compressedBytes" => byte_size(gzip),
      "htmlBytes" => byte_size(html),
      "sha256" => :crypto.hash(:sha256, gzip) |> Base.encode16(case: :lower)
    }
    |> then(fn record ->
      case attrs["data-fog-of-war-max-age-ms"] do
        nil ->
          record

        value ->
          case Integer.parse(value) do
            {ms, ""} when ms > 0 and ms <= 8_000_000_000_000_000 ->
              Map.put(record, "expiresAt", DateTime.to_unix(saved_at, :millisecond) + ms)

            _ ->
              Mix.raise("#{path}: invalid FogOfWar max age")
          end
      end
    end)
  end

  @doc "Write the bundle index from the captured route records and return it."
  def finish!(manifest, pages, root, opts \\ []) do
    index = %{
      "schema" => 1,
      "format" => "fog-of-war-public-cache",
      "scope" => "public",
      "origin" => manifest["web"]["origin"],
      "capture_origin" => capture_origin!(manifest, opts),
      "environment" => manifest["environment"],
      "start_path" => manifest["web"]["start_path"],
      "startup" => "startup.html",
      "pages" => pages
    }

    write!(root, "index.json", Jason.encode!(index, pretty: true))
    index
  end

  defp write!(root, file, body) do
    target = Path.join(root, file)
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, body)
  end
end
