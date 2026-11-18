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
    {tree, deferred} =
      html
      |> Floki.parse_document!()
      |> Floki.traverse_and_update([], &inline_node(&1, &2, assets, origin, stage))

    tree |> append_scripts(Enum.reverse(deferred)) |> Floki.raw_html()
  end

  defp inline_node({"script", attrs, _children} = node, deferred, assets, origin, stage) do
    case Map.new(attrs) do
      %{"src" => src} = options when is_binary(src) ->
        validate_script!(src, options)
        url = resolve_same_origin!(src, origin <> "/", origin, "external script")
        content = url.path |> read_asset!(src, assets, stage) |> safe_script()
        script = {"script", Enum.reject(attrs, fn {key, _} -> key in ["src", "defer"] end), [content]}
        place_script(script, options["defer"], deferred)

      _ ->
        {node, deferred}
    end
  end

  defp inline_node({"link", attrs, _children} = node, deferred, assets, origin, stage) do
    options = Map.new(attrs)
    href = options["href"]

    if "stylesheet" in String.split(options["rel"] || "", ~r/\s+/) and href do
      url = resolve_same_origin!(href, origin <> "/", origin, "stylesheet")
      css = url.path |> expand_css!(assets, stage, origin, MapSet.new()) |> safe_style()
      style = {"style", Enum.filter(attrs, fn {key, _} -> key == "media" end), [css]}
      {style, deferred}
    else
      {node, deferred}
    end
  end

  defp inline_node(node, deferred, _assets, _origin, _stage), do: {node, deferred}

  defp validate_script!(src, options) do
    type = options["type"]

    cond do
      options["async"] != nil ->
        fail("async external script is unsupported: #{src}")

      type in ["module", "importmap"] ->
        fail("module/importmap script is unsupported: #{src}")

      type not in [nil, "", "text/javascript", "application/javascript"] ->
        fail("non-classic external script type is unsupported: #{src}")

      true ->
        :ok
    end
  end

  defp place_script(script, nil, deferred), do: {script, deferred}

  defp place_script(script, _defer, deferred),
    do: {{:comment, " deferred startup script inlined at body end "}, [script | deferred]}

  defp append_scripts(tree, []), do: tree

  defp append_scripts(tree, scripts) do
    Floki.traverse_and_update(tree, fn
      {"body", attrs, children} -> {"body", attrs, children ++ scripts}
      node -> node
    end)
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
          url = resolve_same_origin!(ref, origin <> path, origin, "CSS @import")
          imported = expand_css!(url.path, assets, stage, origin, seen)
          if String.trim(media) == "", do: imported, else: "@media #{media} {#{imported}}"
        end
      )

    Regex.replace(~r/url\(\s*(["']?)([^"')]+)\1\s*\)/i, css, fn full, quote, ref ->
      url = resolve(ref, origin <> path)

      cond do
        not same_origin?(url, origin) ->
          full

        Map.has_key?(assets, url.path) ->
          css_asset_url(url, quote, ref, assets, stage)

        true ->
          fail("CSS resource was not gathered: #{url.path}")
      end
    end)
  end

  defp css_asset_url(url, quote, ref, assets, stage) do
    if Path.extname(url.path) in [".ttf", ".otf", ".woff", ".woff2"] do
      bytes = read_asset!(url.path, ref, assets, stage)
      "url(\"data:#{MIME.from_path(url.path)};base64,#{Base.encode64(bytes)}\")"
    else
      "url(#{quote}fog-of-war-assets://bundle#{url.path}#{suffix(url)}#{quote})"
    end
  end

  defp resolve_same_origin!(ref, base, origin, label) do
    url = resolve(ref, base)
    if !same_origin?(url, origin), do: fail("cross-origin #{label} is unsupported: #{ref}")
    url
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
