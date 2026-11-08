defmodule FogOfWar.Wrapper.NativeBundle do
  @moduledoc "Prepares executable public startup HTML and allowlisted native assets."
  alias FogOfWar.Wrapper.{CacheExport, Export, InlineAssets}

  def run!(manifest, project, output, platform, opts \\ [])
      when platform in ["android", "ios", "apple"] do
    if File.exists?(output), do: Mix.raise("Native bundle destination exists: #{output}")
    stage = output <> ".tmp-#{System.unique_integer([:positive])}"

    try do
      index = CacheExport.run!(manifest, stage, opts)

      references =
        Enum.reduce(
          index["pages"],
          references(File.read!(Path.join(stage, "startup.html"))),
          fn {_, page}, refs ->
            html = :zlib.gunzip(File.read!(Path.join(stage, page["file"])))
            references(html) ++ refs
          end
        )
        |> Enum.uniq()

      assets = Export.copy_assets!(references, project, manifest, stage, %{})
      origin = index["origin"]
      apple_scheme? = platform in ["ios", "apple"]
      startup = File.read!(Path.join(stage, "startup.html"))

      startup =
        if apple_scheme?, do: InlineAssets.inline(startup, assets, origin, stage), else: startup

      asset_url = fn path ->
        if apple_scheme?, do: "fog-of-war-assets://bundle" <> path, else: origin <> path
      end

      # Rewrite parsed URL attributes only. Navigation hrefs and LiveView tokens stay intact.
      rewrite = fn html -> rewrite_html(html, assets, origin, asset_url) end

      if apple_scheme? do
        for {path, file} <- assets, Path.extname(path) == ".css" do
          target = Path.join(stage, file)
          css = File.read!(target)

          css =
            Regex.replace(
              ~r/(url\(\s*["']?)([^\s"'\)]+)(["']?\s*\))|(@import\s+["'])([^"']+)(["'])/,
              css,
              fn _, a, ref, z, b, import_ref, c ->
                value = if ref == "", do: import_ref, else: ref
                url = URI.merge(origin <> path, value)

                changed =
                  if same_origin?(url, origin) && Map.has_key?(assets, url.path),
                    do: asset_url.(url.path) <> suffix(url),
                    else: value

                if ref == "", do: b <> changed <> c, else: a <> changed <> z
              end
            )

          File.write!(target, css)
        end
      end

      pages =
        Map.new(index["pages"], fn {path, record} ->
          file = Path.join(stage, record["file"])
          html = File.read!(file) |> :zlib.gunzip() |> rewrite.()
          gzip = :zlib.gzip(html)
          File.write!(file, gzip)

          {path,
           Map.merge(record, %{
             "compressedBytes" => byte_size(gzip),
             "htmlBytes" => byte_size(html),
             "sha256" => Base.encode16(:crypto.hash(:sha256, gzip), case: :lower)
           })}
        end)

      index = Map.put(index, "pages", pages)
      File.write!(Path.join(stage, "index.json"), Jason.encode!(index))

      prefix =
        if apple_scheme?,
          do: "fog-of-war-assets://bundle/__fog_of_war_bundle/",
          else: origin <> "/__fog_of_war_bundle/"

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

      files =
        Map.new(assets, fn {path, file} ->
          {asset_url.(path), %{"file" => file, "mime" => MIME.from_path(path)}}
        end)

      metadata_files = [{"index.json", "application/json"}]

      metadata_files =
        if apple_scheme?,
          do: metadata_files,
          else: [{"boot.js", "text/javascript"} | metadata_files]

      files =
        Enum.reduce(
          metadata_files ++
            Enum.map(pages, fn {_, p} -> {p["file"], "application/octet-stream"} end),
          files,
          fn {file, mime}, acc ->
            Map.put(acc, prefix <> file, %{"file" => file, "mime" => mime})
          end
        )

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

  defp references(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(
      "script[src],link[rel=stylesheet],link[rel=icon],link[rel=preload],img[src],source[src],video[poster]"
    )
    |> Enum.flat_map(fn {_, attrs, _} ->
      for {key, value} <- attrs, key in ["src", "href", "poster"], do: value
    end)
  end

  defp rewrite_html(html, assets, origin, asset_url) do
    html
    |> Floki.parse_document!()
    |> Floki.traverse_and_update(fn
      {tag, attrs, children} ->
        attrs =
          Enum.map(attrs, fn {key, value} ->
            if key in ["src", "poster"] || (key == "href" && tag == "link") do
              url = URI.merge(origin <> "/", value)

              if same_origin?(url, origin) && Map.has_key?(assets, url.path),
                do: {key, asset_url.(url.path) <> suffix(url)},
                else: {key, value}
            else
              {key, value}
            end
          end)

        {tag, attrs, children}

      other ->
        other
    end)
    |> Floki.raw_html()
  end

  defp same_origin?(uri, origin),
    do: URI.to_string(%{uri | path: nil, query: nil, fragment: nil}) == origin

  defp suffix(uri),
    do:
      if(uri.query, do: "?" <> uri.query, else: "") <>
        if(uri.fragment, do: "#" <> uri.fragment, else: "")
end
