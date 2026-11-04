defmodule FogOfWar.Wrapper.Manifest do
  @moduledoc "A reviewable, JSON-only contract between a Phoenix app and its native wrappers."
  @schema 2

  def discover(opts) do
    config = Mix.Project.config()
    app = config[:app]
    env = Application.get_all_env(app)

    endpoint =
      (opts[:endpoint] && Module.concat([opts[:endpoint]])) ||
        Enum.find_value(env, fn {key, value} ->
          if is_atom(key) && String.ends_with?(Atom.to_string(key), ".Endpoint") && is_list(value),
            do: key
        end)

    if is_nil(endpoint),
      do: Mix.raise("Cannot infer the Phoenix endpoint; pass --endpoint MyAppWeb.Endpoint")

    endpoint_config = Application.get_env(app, endpoint, [])
    url = endpoint_config[:url] || []
    scheme = to_string(url[:scheme] || "http")

    port =
      url[:port] || get_in(endpoint_config, [:http, :port]) ||
        if(scheme == "https", do: 443, else: 4000)

    origin = opts[:url] || "#{scheme}://#{url[:host] || "localhost"}:#{port}"

    router =
      endpoint
      |> Atom.to_string()
      |> String.replace_suffix(".Endpoint", ".Router")
      |> String.to_atom()

    routes =
      if Code.ensure_loaded?(router) && function_exported?(router, :__routes__, 0) do
        Phoenix.Router.routes(router)
        |> Enum.filter(&(&1.verb == :get))
        |> Enum.map(& &1.path)
        |> Enum.uniq()
        |> Enum.sort()
      else
        []
      end

    slug = opts[:slug] || to_string(app)
    static = "priv/static"

    icon =
      Enum.find(
        ["images/icon.png", "images/logo.png", "images/logo.svg", "favicon.ico"],
        &File.regular?(Path.join(static, &1))
      )

    %{
      "schema" => @schema,
      "default_env" => "dev",
      "envs" => %{"dev" => %{}},
      "app" => %{
        "name" => opts[:name] || Macro.camelize(slug),
        "slug" => slug,
        "identifier" => opts[:identifier] || "dev.fogofwar.#{String.replace(slug, "_", "")}",
        "version" => config[:version] || "0.1.0",
        "icon" => icon && Path.join(static, icon)
      },
      "web" => %{
        "origin" => origin,
        "start_path" => "/",
        "endpoint" => inspect(endpoint),
        "router" => inspect(router),
        "discovered_routes" => routes
      },
      "public" => %{
        "paths" => Keyword.get_values(opts, :public),
        "static_root" => static,
        "bundle" => ".fow/public",
        "asset_directories" => ["assets", "css", "fonts", "images"],
        "note" =>
          "Only list routes whose unauthenticated rendered content may be distributed publicly. No cookies are exported."
      },
      "mob" => %{"platforms" => ["android", "ios"]},
      "elixirkit" => %{"width" => 1060, "height" => 760}
    }
    |> tap(&resolve!/1)
  end

  def read!(path, env \\ nil), do: path |> File.read!() |> Jason.decode!() |> resolve!(env)

  @doc "Merge a named environment over top-level defaults, then validate the result."
  def resolve!(document, env \\ nil) when is_map(document) do
    unless document["schema"] in [1, 2],
      do: Mix.raise("Unsupported .fow.json schema; expected 1 or 2")

    case Map.fetch(document, "envs") do
      :error ->
        if env && env != document["environment"],
          do: Mix.raise("Manifest has no environment #{inspect(env)}")

        validate!(document)

      {:ok, profiles} when is_map(profiles) ->
        name = env || document["default_env"] || "dev"

        unless is_binary(name) && Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9_-]*$/, name),
          do:
            Mix.raise(
              "Environment names must be nonempty letters, digits, underscores or hyphens"
            )

        overrides = Map.get(profiles, name)

        unless is_map(overrides),
          do:
            Mix.raise(
              "Unknown or invalid environment #{inspect(name)}; available: #{Enum.join(Map.keys(profiles), ", ")}"
            )

        if Enum.any?(
             ["schema", "envs", "default_env", "environment"],
             &Map.has_key?(overrides, &1)
           ),
           do: Mix.raise("Environment overrides cannot replace manifest control fields")

        resolved =
          document
          |> Map.drop(["envs", "default_env"])
          |> deep_merge(overrides)
          |> Map.put("environment", name)
          |> validate!()

        # Isolate generated artifacts even when profiles inherit the same output defaults.
        update_in(resolved, ["public", "bundle"], &Path.join(&1, name))

      _ ->
        Mix.raise("envs must be a map of environment names to override maps")
    end
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, a, b when is_map(a) and is_map(b) -> deep_merge(a, b)
      _key, _a, b -> b
    end)
  end

  def validate!(%{"schema" => schema, "app" => app, "web" => web, "public" => public} = manifest)
      when schema in [1, 2] and is_map(app) and is_map(web) and is_map(public) do
    require_match!(
      app["slug"],
      ~r/^[a-z][a-z0-9_]*$/,
      "app.slug must be a lowercase Elixir application name"
    )

    require_match!(
      app["identifier"],
      ~r/^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*){2,}$/,
      "app.identifier must be a reverse-domain identifier"
    )

    require_match!(app["version"], ~r/^\d+\.\d+\.\d+$/, "app.version must be x.y.z")

    if !is_binary(app["name"]) || String.trim(app["name"]) == "",
      do: Mix.raise("app.name is required")

    if String.contains?(app["name"], ["/", "\\"]) || Regex.match?(~r/[\x00-\x1F]/, app["name"]),
      do:
        Mix.raise(
          "app.name must be a display name, without path separators or control characters"
        )

    origin = validate_origin!(web["origin"], "web.origin")

    if capture = manifest["capture"] do
      unless is_map(capture), do: Mix.raise("capture must be a map")
      if capture["origin"], do: validate_origin!(capture["origin"], "capture.origin")
    end

    validate_path!(web["start_path"])

    unless is_list(public["paths"]),
      do: Mix.raise("public.paths must explicitly list public route paths")

    Enum.each(public["paths"], &validate_path!/1)
    for key <- ["static_root", "bundle"], do: relative_path!(public[key])

    unless is_list(public["asset_directories"]),
      do: Mix.raise("public.asset_directories must be a list")

    Enum.each(public["asset_directories"], &relative_path!/1)
    platforms = get_in(manifest, ["mob", "platforms"]) || ["android", "ios"]

    unless platforms != [] && Enum.all?(platforms, &(&1 in ["android", "ios"])),
      do: Mix.raise("mob.platforms must list android and/or ios")

    for key <- ["width", "height"] do
      value = get_in(manifest, ["elixirkit", key]) || 760

      unless is_integer(value) && value in 240..4096,
        do: Mix.raise("elixirkit.#{key} must be 240..4096")
    end

    if app["icon"], do: relative_path!(app["icon"])
    %{manifest | "web" => Map.put(web, "origin", origin)}
  end

  def validate!(_),
    do: Mix.raise("Resolved manifest requires schema 1 or 2 and app, web, public maps")

  def validate_origin!(value, label \\ "origin") do
    unless is_binary(value), do: Mix.raise("#{label} must be an HTTP(S) origin")
    uri = URI.parse(value)

    unless uri.scheme in ["http", "https"] && is_binary(uri.host) && uri.userinfo == nil &&
             uri.query == nil && uri.fragment == nil && uri.path in [nil, "", "/"],
           do: Mix.raise("#{label} must be an HTTP(S) origin, without credentials or a path")

    if uri.scheme == "http" && uri.host not in ["localhost", "127.0.0.1", "[::1]", "::1"],
      do: Mix.raise("Use HTTPS for non-loopback origins")

    URI.to_string(%{uri | path: nil, host: String.downcase(uri.host)})
  end

  def validate_path!(path) do
    unless is_binary(path) && String.starts_with?(path, "/") && !String.starts_with?(path, "//") &&
             !String.contains?(path, ["?", "#", "\\", "\0"]) &&
             !Enum.any?(String.split(URI.decode(path), "/"), &(&1 in ["..", "."])),
           do: Mix.raise("Expected a concrete route path, got #{inspect(path)}")

    path
  end

  def relative_path!(path) do
    unless is_binary(path) && path != "" && Path.type(path) == :relative &&
             !Enum.any?(Path.split(path), &(&1 in ["..", "."])) &&
             !String.contains?(path, ["\\", "\0"]),
           do: Mix.raise("Expected a project-relative path, got #{inspect(path)}")

    path
  end

  def write!(path, manifest, force \\ false) do
    if File.exists?(path) && !force, do: Mix.raise("#{path} exists; edit it or pass --force")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, [Jason.encode_to_iodata!(manifest, pretty: true), "\n"])
  end

  defp require_match!(value, regex, message) do
    unless is_binary(value) && Regex.match?(regex, value), do: Mix.raise(message)
  end
end
