defmodule FogOfWar.Wrapper.InlineAssets do
  @moduledoc """
  An offline Apple WebView needs its startup JavaScript and CSS even when the website cannot answer. This module embeds collected same-origin scripts and styles into the startup document so it can run without fetching those files from the site. Native bundle preparation calls it automatically.

  ## How it fits

  Called by `FogOfWar.Wrapper.NativeBundle` when preparing the Apple startup document. App developers normally interact with the bundle preparation task instead.
  """

  @doc """
  Inline gathered same-origin scripts and stylesheets in startup HTML.

  `assets` is the `Export.copy_assets!/5` map (`URL path => stage-relative file`).
  Deferred classic scripts are appended to the body in their original order.
  """
  def inline(html, assets, origin, stage) do
    tree = Floki.parse_document!(html)

    tree =
      Floki.traverse_and_update(tree, fn
        {"script", attrs, _children} = node ->
          attrs_map = Map.new(attrs)

          if attrs_map["src"] do
            src = attrs_map["src"]
            url = resolve(src, origin <> "/")
            same? = same_origin?(url, origin)

            cond do
              attrs_map["async"] != nil ->
                fail("async external script is unsupported: #{src}")

              attrs_map["type"] in ["module", "importmap"] ->
                fail("module/importmap script is unsupported: #{src}")

              attrs_map["type"] not in [nil, "", "text/javascript", "application/javascript"] ->
                fail("non-classic external script type is unsupported: #{src}")

              not same? ->
                fail("cross-origin external script is unsupported: #{src}")

              true ->
                content = url.path |> read_asset!(src, assets, stage) |> safe_script()

                script =
                  {"script", Enum.reject(attrs, fn {k, _} -> k in ["src", "defer"] end), [content]}

                if attrs_map["defer"] == nil do
                  script
                else
                  Process.put(
                    {__MODULE__, :deferred},
                    Process.get({__MODULE__, :deferred}, []) ++ [script]
                  )

                  {:comment, " deferred startup script inlined at body end "}
                end
            end
          else
            node
          end

        {"link", attrs, _children} = node ->
          attrs_map = Map.new(attrs)

          if "stylesheet" in String.split(attrs_map["rel"] || "", ~r/\s+/) and attrs_map["href"] do
            href = attrs_map["href"]
            url = resolve(href, origin <> "/")

            if same_origin?(url, origin) do
              css = url.path |> expand_css!(assets, stage, origin, MapSet.new()) |> safe_style()
              {"style", Enum.filter(attrs, fn {key, _} -> key == "media" end), [css]}
            else
              fail("cross-origin stylesheet is unsupported: #{href}")
            end
          else
            node
          end

        other ->
          other
      end)

    scripts = Process.delete({__MODULE__, :deferred}) || []

    tree =
      if scripts == [] do
        tree
      else
        Floki.traverse_and_update(tree, fn
          {"body", attrs, children} -> {"body", attrs, children ++ scripts}
          node -> node
        end)
      end

    Floki.raw_html(tree)
  after
    Process.delete({__MODULE__, :deferred})
  end

  defp expand_css!(path, assets, stage, origin, seen) do
    if MapSet.member?(seen, path), do: fail("CSS @import cycle at #{path}")
    css = read_asset!(path, path, assets, stage)
    seen = MapSet.put(seen, path)

    if Regex.match?(~r/@import[^;]*?\b(?:layer|supports)\b(?:\s*\(|\s|;)/i, css) do
      fail("CSS @import layer() and supports() conditions are unsupported in #{path}")
    end

    css =
      Regex.replace(
        ~r/@import\s+(?:url\(\s*)?["']?([^\s"')]+)["']?\s*\)?\s*([^;]*);/i,
        css,
        fn _full, ref, media ->
          url = resolve(ref, origin <> path)

          if same_origin?(url, origin) do
            imported = expand_css!(url.path, assets, stage, origin, seen)
            if String.trim(media) == "", do: imported, else: "@media #{media} {#{imported}}"
          else
            fail("cross-origin CSS @import is unsupported: #{ref}")
          end
        end
      )

    Regex.replace(~r/url\(\s*(["']?)([^"')]+)\1\s*\)/i, css, fn full, quote, ref ->
      url = resolve(ref, origin <> path)

      cond do
        not same_origin?(url, origin) ->
          full

        Map.has_key?(assets, url.path) ->
          if Path.extname(url.path) in [".ttf", ".otf", ".woff", ".woff2"] do
            bytes = read_asset!(url.path, ref, assets, stage)
            "url(\"data:#{MIME.from_path(url.path)};base64,#{Base.encode64(bytes)}\")"
          else
            "url(#{quote}#{"fog-of-war-assets://bundle" <> url.path}#{suffix(url)}#{quote})"
          end

        true ->
          fail("CSS resource was not gathered: #{url.path}")
      end
    end)
  end

  defp read_asset!(path, label, assets, stage) do
    case Map.get(assets, path) do
      nil -> fail("startup dependency was not gathered: #{label} (#{path})")
      file -> File.read!(Path.join(stage, file))
    end
  end

  defp resolve(ref, base), do: URI.merge(base, ref)

  defp same_origin?(uri, origin), do: URI.to_string(%{uri | path: nil, query: nil, fragment: nil}) == origin

  defp suffix(uri),
    do: if(uri.query, do: "?" <> uri.query, else: "") <> if(uri.fragment, do: "#" <> uri.fragment, else: "")

  defp safe_script(text), do: Regex.replace(~r{</script}i, text, "<\\/script")
  defp safe_style(text), do: Regex.replace(~r{</style}i, text, "<\\/style")
  defp fail(message), do: raise(ArgumentError, "Cannot inline Apple startup assets: " <> message)
end
