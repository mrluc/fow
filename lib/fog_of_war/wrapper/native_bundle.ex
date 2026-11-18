defmodule FogOfWar.Wrapper.NativeBundle do
  @moduledoc """
  Turns public route captures into files a native WebView can serve at startup. Android and Apple use different asset loading mechanisms, so each gets its own prepared directory. Use `mix fow.bundle.prepare` to produce one.

  ## How it fits

  Called by `mix fow.bundle.prepare` and directly by `FogOfWar.Wrapper.Workflow.desktop!/2`. It uses `CacheExport` for routes, `Export` for assets and `InlineAssets` for Apple startup documents.
  """
  alias FogOfWar.Wrapper.CacheExport
  alias FogOfWar.Wrapper.Export
  alias FogOfWar.Wrapper.InlineAssets

  @doc "Capture public routes, prepare startup HTML and assets for the selected platform, and return the native resource manifest. Supply a resolved manifest and a fresh output directory."
  def run!(manifest, project, output, platform, opts \\ []) when platform in ["android", "ios", "apple"] do
    if File.exists?(output), do: Mix.raise("Native bundle destination exists: #{output}")
    stage = output <> ".tmp-#{System.unique_integer([:positive])}"

    try do
      index = CacheExport.run!(manifest, stage, opts)

      references = bundle_references(index, stage)
      assets = Export.copy_assets!(references, project, manifest, stage, %{})
      origin = index["origin"]
      apple_scheme? = platform in ["ios", "apple"]
      startup = startup_html(stage, assets, origin, apple_scheme?)

      asset_origin = if apple_scheme?, do: "fog-of-war-assets://bundle", else: origin
      asset_url = &(asset_origin <> &1)

      # Rewrite parsed URL attributes only. Navigation hrefs and LiveView tokens stay intact.
      rewrite = fn html -> rewrite_html(html, assets, origin, asset_url) end

      if apple_scheme?, do: rewrite_stylesheets!(stage, assets, origin, asset_url)

      pages = rewrite_pages!(index["pages"], stage, rewrite)
      File.write!(Path.join(stage, "index.json"), Jason.encode!(%{index | "pages" => pages}))

      prefix = asset_url.("/__fog_of_war_bundle/")
      write_startup!(startup, assets, stage, prefix, asset_url, rewrite, apple_scheme?)
      files = bundle_files(assets, pages, prefix, asset_url, apple_scheme?)

      native = %{
        "schema" => 1,
        "platform" => platform,
        "url" => origin <> index["start_path"],
        "startup" => "startup.html",
        "files" => files
      }

      File.write!(Path.join(stage, "native.json"), Jason.encode!(native, pretty: true))
      File.mkdir_p!(Path.dirname(output))
      File.rename!(stage, output)
      native
    after
      File.rm_rf(stage)
    end
  end

  defp bundle_references(index, stage) do
    index["pages"]
    |> Enum.reduce(
      references(File.read!(Path.join(stage, "startup.html"))),
      fn {_, page}, refs ->
        html = :zlib.gunzip(File.read!(Path.join(stage, page["file"])))
        references(html) ++ refs
      end
    )
    |> Enum.uniq()
  end

  defp startup_html(stage, assets, origin, apple_scheme?) do
    startup = File.read!(Path.join(stage, "startup.html"))
    if apple_scheme?, do: InlineAssets.inline(startup, assets, origin, stage), else: startup
  end

  defp rewrite_stylesheets!(stage, assets, origin, asset_url) do
    for {path, file} <- assets, Path.extname(path) == ".css" do
      target = Path.join(stage, file)
      css = rewrite_css(File.read!(target), origin <> path, assets, origin, asset_url)
      File.write!(target, css)
    end
  end

  defp rewrite_css(css, base, assets, origin, asset_url) do
    Regex.replace(
      ~r/(url\(\s*["']?)([^\s"'\)]+)(["']?\s*\))|(@import\s+["'])([^"']+)(["'])/,
      css,
      fn _, before_url, ref, after_url, before_import, import_ref, after_import ->
        case ref do
          "" ->
            before_import <> rewrite_url(import_ref, base, assets, origin, asset_url) <> after_import

          _ ->
            before_url <> rewrite_url(ref, base, assets, origin, asset_url) <> after_url
        end
      end
    )
  end

  defp rewrite_pages!(pages, stage, rewrite) do
    Map.new(pages, fn {path, record} ->
      file = Path.join(stage, record["file"])
      html = file |> File.read!() |> :zlib.gunzip() |> rewrite.()
      gzip = :zlib.gzip(html)
      File.write!(file, gzip)

      {path,
       Map.merge(record, %{
         "compressedBytes" => byte_size(gzip),
         "htmlBytes" => byte_size(html),
         "sha256" => Base.encode16(:crypto.hash(:sha256, gzip), case: :lower)
       })}
    end)
  end

  defp write_startup!(startup, assets, stage, prefix, asset_url, rewrite, apple_scheme?) do
    boot = %{
      indexURL: prefix <> "index.json",
      assets: Map.new(assets, fn {path, _} -> {path, asset_url.(path)} end)
    }

    boot_script =
      "window.__fogOfWarNativeBundle=" <>
        String.replace(Jason.encode!(boot), "<", "\\u003c") <> ";"

    boot_tag =
      if apple_scheme? do
        {"script", [], [boot_script]}
      else
        File.write!(Path.join(stage, "boot.js"), boot_script)
        {"script", [{"src", prefix <> "boot.js"}], []}
      end

    html =
      startup
      |> rewrite.()
      |> Floki.parse_document!()
      |> Floki.traverse_and_update(fn
        {"head", attrs, children} ->
          {"head", attrs, [boot_tag | children]}

        other ->
          other
      end)
      |> Floki.raw_html()

    File.write!(Path.join(stage, "startup.html"), "<!doctype html>\n" <> html)
  end

  defp bundle_files(assets, pages, prefix, asset_url, apple_scheme?) do
    files =
      Map.new(assets, fn {path, file} ->
        {asset_url.(path), %{"file" => file, "mime" => MIME.from_path(path)}}
      end)

    metadata_files = [{"index.json", "application/json"}]

    metadata_files =
      if apple_scheme?,
        do: metadata_files,
        else: [{"boot.js", "text/javascript"} | metadata_files]

    Enum.reduce(
      metadata_files ++
        Enum.map(pages, fn {_, p} -> {p["file"], "application/octet-stream"} end),
      files,
      fn {file, mime}, acc ->
        Map.put(acc, prefix <> file, %{"file" => file, "mime" => mime})
      end
    )
  end

  defp references(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("script[src],link[rel=stylesheet],link[rel=icon],link[rel=preload],img[src],source[src],video[poster]")
    |> Enum.flat_map(fn {_, attrs, _} ->
      for {key, value} <- attrs, key in ["src", "href", "poster"], do: value
    end)
  end

  defp rewrite_html(html, assets, origin, asset_url) do
    html
    |> Floki.parse_document!()
    |> Floki.traverse_and_update(fn
      {tag, attrs, children} ->
        attrs = Enum.map(attrs, &rewrite_attr(&1, tag, assets, origin, asset_url))
        {tag, attrs, children}

      other ->
        other
    end)
    |> Floki.raw_html()
  end

  defp rewrite_attr({key, value}, tag, assets, origin, asset_url)
       when key in ["src", "poster"] or (key == "href" and tag == "link") do
    {key, rewrite_url(value, origin <> "/", assets, origin, asset_url)}
  end

  defp rewrite_attr(attr, _tag, _assets, _origin, _asset_url), do: attr

  defp rewrite_url(value, base, assets, origin, asset_url) do
    url = URI.merge(base, value)

    if same_origin?(url, origin) && Map.has_key?(assets, url.path),
      do: asset_url.(url.path) <> suffix(url),
      else: value
  end

  defp same_origin?(uri, origin), do: URI.to_string(%{uri | path: nil, query: nil, fragment: nil}) == origin

  defp suffix(uri),
    do: if(uri.query, do: "?" <> uri.query, else: "") <> if(uri.fragment, do: "#" <> uri.fragment, else: "")
end
