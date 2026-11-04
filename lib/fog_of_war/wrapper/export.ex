defmodule FogOfWar.Wrapper.Export do
  @moduledoc "Exports explicitly public, unauthenticated HTML and reachable static assets."
  alias FogOfWar.Wrapper.{Manifest, CacheExport}
  @build "fog-of-war-2"
  @removed ~w(script iframe object embed base)
  @unsafe_attrs ~w(action formaction nonce integrity)

  def run!(manifest, project, output, opts \\ []) do
    paths = manifest["public"]["paths"] |> Enum.uniq()

    if paths == [],
      do: Mix.raise("Set public.paths explicitly before export; no routes are assumed public")

    unless manifest["web"]["start_path"] in paths,
      do: Mix.raise("web.start_path must be one of public.paths")

    if File.exists?(output),
      do:
        Mix.raise(
          "Export destination exists: #{output}; use a fresh path and review it before replacing a bundle"
        )

    origin = CacheExport.capture_origin!(manifest, opts)
    stage = output <> ".tmp-#{System.unique_integer([:positive])}"
    File.mkdir_p!(stage)
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    try do
      pages =
        Map.new(paths, fn path ->
          fetch = opts[:fetch] || (&fetch_html!/1)
          body = fetch.(origin <> path)

          cache_record =
            CacheExport.capture!(manifest, path, body, Path.join(stage, "cache"), opts)

          document = Floki.parse_document!(body)
          title = document |> Floki.find("title") |> Floki.text()
          region = Floki.find(document, "[phx-hook=FogOfWar]")

          raw_region =
            case region do
              [node] ->
                node

              [] ->
                {"main", [{"id", "fog-of-war-public-page"}],
                 Floki.find(document, "body")
                 |> Enum.flat_map(fn {_, _, children} -> children end)}

              _ ->
                Mix.raise(
                  "#{path} has multiple FogOfWar regions; export expects one whole-page region"
                )
            end

          sanitized = sanitize(document, manifest["web"]["origin"])
          snapshot_html = sanitize([raw_region], manifest["web"]["origin"]) |> Floki.raw_html()

          name =
            "pages/" <> (:crypto.hash(:sha256, path) |> Base.encode16(case: :lower)) <> ".html"

          html = Floki.raw_html(sanitized)
          # The public shell has no LiveSocket or credentials. Only our bundled script runs.
          policy =
            "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'none'; form-action 'none'; object-src 'none'; base-uri 'none'"

          html =
            String.replace(
              html,
              "</head>",
              "<meta http-equiv=\"Content-Security-Policy\" content=\"#{policy}\"><script defer src=\"/_fog/bootstrap.js\"></script></head>"
            )

          write!(stage, name, "<!doctype html>\n" <> html)

          snapshot = %{
            "schema" => 1,
            "build" => @build,
            "path" => path,
            "title" => title,
            "regionId" => elem(raw_region, 1) |> Map.new() |> Map.get("id"),
            "savedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "html" => snapshot_html
          }

          {path, %{"file" => name, "snapshot" => snapshot, "cache" => cache_record}}
        end)

      cache_pages = Map.new(pages, fn {path, page} -> {path, page["cache"]} end)
      CacheExport.finish!(manifest, cache_pages, Path.join(stage, "cache"), opts)

      cache_files =
        ["cache/index.json", "cache/startup.html"] ++
          Enum.map(cache_pages, fn {_, record} -> "cache/" <> record["file"] end)

      references =
        Enum.flat_map(pages, fn {_, page} ->
          html = File.read!(Path.join(stage, page["file"]))

          html
          |> Floki.parse_document!()
          |> Floki.find("link[rel=stylesheet],link[rel=icon],img[src],source[src],video[poster]")
          |> Enum.flat_map(fn {_, attrs, _} ->
            for {k, v} <- attrs, k in ["href", "src", "poster"], do: v
          end)
        end)

      assets = copy_assets!(references, project, manifest, stage, %{})

      bundle = %{
        "schema" => 1,
        "environment" => manifest["environment"],
        "cache" => %{"index" => "cache/index.json", "files" => cache_files},
        "scope" => "public",
        "origin" => manifest["web"]["origin"],
        "start_path" => manifest["web"]["start_path"],
        "name" => manifest["app"]["name"],
        "pages" => pages,
        "assets" => assets
      }

      write!(stage, "bundle.json", Jason.encode!(bundle, pretty: true))
      bootstrap = File.read!(Application.app_dir(:fow, "priv/templates/wrapper/bootstrap.js"))

      write!(
        stage,
        "_fog/bootstrap.js",
        String.replace(bootstrap, "__FOG_BUNDLE__", Jason.encode!(bundle))
      )

      File.mkdir_p!(Path.dirname(output))
      File.rename!(stage, output)
      bundle
    after
      File.rm_rf(stage)
    end
  end

  def seed_script(bundle) do
    snapshots = Enum.map(bundle["pages"], fn {_, page} -> page["snapshot"] end)

    """
    (() => {
      if (window.top !== window || location.origin !== #{Jason.encode!(bundle["origin"])}) return;
      const snapshots = #{Jason.encode!(snapshots)};
      try { for (const snapshot of snapshots) {
        const key = 'fog-of-war:page:' + snapshot.path;
        if (localStorage.getItem(key) === null) localStorage.setItem(key, JSON.stringify(snapshot));
      }} catch (_) { /* Storage policy may disable preload; online loading still works. */ }
    })();
    """
  end

  @doc false
  def fetch_html!(url) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    # An isolated profile cannot inherit a caller's HTTP cookie jar.
    {:ok, profile} = :inets.start(:httpc, profile: :fog_of_war_public_export)

    result =
      try do
        :httpc.request(
          :get,
          {String.to_charlist(url), []},
          [timeout: 10_000, autoredirect: false, ssl: ssl],
          [body_format: :binary],
          profile
        )
      after
        :inets.stop(:httpc, profile)
      end

    case result do
      {:ok, {{_, 200, _}, headers, body}} when byte_size(body) <= 2_000_000 ->
        type =
          Enum.find_value(headers, "", fn {k, v} ->
            if String.downcase(to_string(k)) == "content-type", do: to_string(v)
          end)

        unless String.starts_with?(type, "text/html"),
          do: Mix.raise("Expected public HTML from #{url}, got #{type}")

        body

      {:ok, {{_, 200, _}, _, body}} when byte_size(body) > 2_000_000 ->
        Mix.raise("Public HTML exceeds the 2,000,000-byte per-page limit: #{url}")

      {:ok, {{_, status, _}, _, _}} ->
        Mix.raise("Public export requires HTTP 200 without redirects: #{url} returned #{status}")

      {:error, reason} ->
        Mix.raise("Could not export #{url}: #{inspect(reason)}")
    end
  end

  defp sanitize(nodes, origin) do
    Enum.flat_map(nodes, fn
      {tag, attrs, children} ->
        values = Map.new(attrs)

        cond do
          tag in @removed || values["phx-hook"] == "FogOfWarDevTools" ||
            (tag == "meta" && values["name"] == "csrf-token") ||
              (tag == "input" && values["type"] in ["hidden", "password"]) ->
            []

          true ->
            attrs =
              Enum.reject(attrs, fn {key, _} ->
                String.starts_with?(key, ["phx-", "data-phx-", "on"]) || key in @unsafe_attrs
              end)

            attrs =
              Enum.flat_map(attrs, fn
                {key, value} when key in ["href", "src", "poster"] ->
                  cond do
                    String.starts_with?(value, origin <> "/") ->
                      [{key, String.replace_prefix(value, origin, "")}]

                    String.starts_with?(value, ["javascript:", "vbscript:"]) ->
                      []

                    true ->
                      [{key, value}]
                  end

                attr ->
                  [attr]
              end)

            attrs =
              if tag in ~w(button input textarea select),
                do: [{"disabled", "disabled"}, {"aria-disabled", "true"} | attrs],
                else: attrs

            [{tag, attrs, sanitize(children, origin)}]
        end

      text when is_binary(text) ->
        [text]

      _ ->
        []
    end)
  end

  defp copy_assets!([], _project, _manifest, _stage, found), do: found

  defp copy_assets!([url | rest], project, manifest, stage, found) do
    uri = URI.parse(url)
    origin = manifest["web"]["origin"]
    local = is_nil(uri.host) || String.starts_with?(url, origin <> "/")
    path = uri.path || ""

    cond do
      !local || path == "" || String.starts_with?(path, "/_fog/") || Map.has_key?(found, path) ->
        copy_assets!(rest, project, manifest, stage, found)

      true ->
        path = if String.starts_with?(path, "/"), do: path, else: "/" <> path
        Manifest.validate_path!(path)
        relative = URI.decode(String.trim_leading(path, "/"))
        root = Path.expand(manifest["public"]["static_root"], project)
        source = Path.join(root, relative)

        allowed =
          Enum.any?(
            manifest["public"]["asset_directories"],
            &String.starts_with?(relative, &1 <> "/")
          ) || relative == "favicon.ico"

        if !allowed || !File.regular?(source),
          do:
            Mix.raise(
              "Missing or disallowed public asset #{path}; adjust public.asset_directories"
            )

        reject_symlinks!(root, relative)

        if map_size(found) > 512 || File.stat!(source).size > 10_000_000,
          do: Mix.raise("Public asset export limit exceeded")

        target = "assets/" <> relative
        data = File.read!(source)
        write!(stage, target, data)

        urls =
          if Path.extname(path) == ".css" do
            Regex.scan(~r/(?:url\(\s*|@import\s+)["']?([^\s"'\)]+)["']?\s*\)?/, data)
            |> Enum.map(fn [_, ref] -> URI.merge("http://local" <> path, ref) end)
            |> Enum.filter(&(&1.host == "local"))
            |> Enum.map(& &1.path)
          else
            []
          end

        copy_assets!(rest ++ urls, project, manifest, stage, Map.put(found, path, target))
    end
  end

  def reject_symlinks!(root, relative) do
    if File.lstat!(root).type == :symlink, do: Mix.raise("Do not export a symlinked static root")

    Enum.reduce(Path.split(relative), root, fn part, parent ->
      path = Path.join(parent, part)

      if File.lstat!(path).type == :symlink,
        do: Mix.raise("Do not export symlinked asset #{path}")

      path
    end)
  end

  defp write!(stage, relative, bytes) do
    path = Path.join(stage, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
  end
end
