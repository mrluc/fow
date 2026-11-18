defmodule FogOfWar.Wrapper.Export do
  @moduledoc "Fetches public HTML and gathers local assets for native bundles."
  alias FogOfWar.Wrapper.Manifest

  @doc "Fetch an anonymous HTML response for public capture."
  def fetch_html!(url) do
    Mix.ensure_application!(:inets)
    Mix.ensure_application!(:ssl)
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

    public_html!(result, url)
  end

  defp public_html!({:ok, {{_, 200, _}, headers, body}}, url) when byte_size(body) <= 2_000_000 do
    type =
      Enum.find_value(headers, "", fn {k, v} ->
        if String.downcase(to_string(k)) == "content-type", do: to_string(v)
      end)

    if !String.starts_with?(type, "text/html"),
      do: Mix.raise("Expected public HTML from #{url}, got #{type}")

    body
  end

  defp public_html!({:ok, {{_, 200, _}, _, _}}, url),
    do: Mix.raise("Public HTML exceeds the 2,000,000-byte per-page limit: #{url}")

  defp public_html!({:ok, {{_, status, _}, _, _}}, url),
    do: Mix.raise("Public export requires HTTP 200 without redirects: #{url} returned #{status}")

  defp public_html!({:error, reason}, url), do: Mix.raise("Could not export #{url}: #{inspect(reason)}")

  @doc "Copy eligible local static assets into staging and return their URL-to-file mapping."
  def copy_assets!([], _project, _manifest, _stage, found), do: found

  def copy_assets!([url | rest], project, manifest, stage, found) do
    uri = URI.parse(url)
    origin = manifest["web"]["origin"]
    local = is_nil(uri.host) || String.starts_with?(url, origin <> "/")
    path = uri.path || ""

    if uri.scheme not in [nil, "http", "https"] || !local || path == "" ||
         String.starts_with?(path, "/_fog/") || Map.has_key?(found, path) do
      copy_assets!(rest, project, manifest, stage, found)
    else
      {path, target, urls} = copy_asset!(path, project, manifest, stage, found)
      copy_assets!(rest ++ urls, project, manifest, stage, Map.put(found, path, target))
    end
  end

  defp copy_asset!(path, project, manifest, stage, found) do
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
      do: Mix.raise("Missing or disallowed public asset #{path}; adjust public.asset_directories")

    reject_symlinks!(root, relative)

    if map_size(found) > 512 || File.stat!(source).size > 10_000_000,
      do: Mix.raise("Public asset export limit exceeded")

    target = "assets/" <> relative
    data = File.read!(source)
    write!(stage, target, data)

    {path, target, asset_references(Path.extname(path), path, data)}
  end

  defp asset_references(".css", path, data) do
    ~r/(?:url\(\s*|@import\s+(?!url\s*\())["']?([^\s"'\)]+)["']?\s*\)?/
    |> Regex.scan(data)
    |> Enum.map(fn [_, ref] -> URI.merge("http://local" <> path, ref) end)
    |> Enum.filter(&(&1.host == "local"))
    |> Enum.map(& &1.path)
  end

  defp asset_references(_extension, _path, _data), do: []

  @doc "Reject symlinks in a relative asset path before copying from the given root."
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
