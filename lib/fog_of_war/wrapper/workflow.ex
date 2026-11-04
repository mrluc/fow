defmodule FogOfWar.Wrapper.Workflow do
  @moduledoc "Build and local installation steps for generated desktop projects."
  alias FogOfWar.Wrapper.{Export, Generator, Manifest, Output}

  def project_path(manifest_path, target, opts \\ []) do
    manifest = Manifest.read!(manifest_path, opts[:env])
    default = Path.join([".fow/apps", to_string(target)] ++ List.wrap(manifest["environment"]))
    Path.expand(opts[:output] || default)
  end

  def build_elixirkit!(project, opts \\ []) do
    project = Path.expand(project)
    manifest = Manifest.read!(Path.join(project, ".fow.json"))

    unless File.regular?(Path.join(project, "build.sh")),
      do: Mix.raise("No build.sh in generated project: #{project}")

    target =
      opts[:target_dir] || System.get_env("CARGO_TARGET_DIR") ||
        Path.join(project, "src-tauri/target")

    target = Path.expand(target, project)
    run!("bash", ["build.sh"], [cd: project, env: [{"CARGO_TARGET_DIR", target}]], opts)

    app =
      Path.join([target, "release/bundle/macos", manifest["app"]["name"] <> ".app"])

    unless File.dir?(app), do: Mix.raise("Build completed but the app was not found: #{app}")
    app
  end

  def install_osx_local!(app, opts \\ []) do
    unless (opts[:os] || :os.type()) == {:unix, :darwin},
      do: Mix.raise("Local macOS installation requires macOS")

    app = Path.expand(app)

    unless String.ends_with?(app, ".app") && File.regular?(Path.join(app, "Contents/Info.plist")),
      do: Mix.raise("Expected a built .app containing Contents/Info.plist: #{app}")

    applications =
      Path.expand(opts[:applications] || Path.join(System.user_home!(), "Applications"))

    destination = Path.join(applications, Path.basename(app))

    if Path.expand(app) == Path.expand(destination),
      do: Mix.raise("The source app is already at the installation destination")

    Output.replace!(destination, [force: opts[:force], protected: [app]], fn stage ->
      run!("/usr/bin/ditto", [app, stage], [], opts)
    end)

    run!(
      "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
      ["-f", destination],
      [],
      opts
    )

    run!("/usr/bin/mdimport", [destination], [], opts)
    destination
  end

  def desktop!(manifest_path, opts \\ []) do
    unless (opts[:os] || :os.type()) == {:unix, :darwin},
      do: Mix.raise("Desktop build/install convenience requires macOS")

    manifest_path = Path.expand(manifest_path)
    manifest = Manifest.read!(manifest_path, opts[:env])
    root = Path.dirname(manifest_path)
    bundle = Path.expand(manifest["public"]["bundle"], root)
    project = project_path(manifest_path, :elixirkit, opts)
    # Reject unsafe outputs before fetching pages or running a build.
    Output.validate!(project, [root, bundle])

    for path <- [bundle, project] do
      if File.exists?(path) && !opts[:force],
        do: Mix.raise("Destination exists: #{path}; pass --force to replace it completely")
    end

    Output.replace!(bundle, [force: opts[:force], protected: [root, project]], fn stage ->
      # The exporter owns its own staging directory and requires a fresh output.
      File.rmdir!(stage)
      Export.run!(manifest, root, stage, base_url: opts[:base_url], fetch: opts[:fetch])
    end)

    Generator.run!(:elixirkit, manifest_path, project, env: opts[:env], force: opts[:force])
    project |> build_elixirkit!(opts) |> install_osx_local!(opts)
  end

  defp run!(command, args, command_opts, opts) do
    runner =
      opts[:runner] ||
        fn cmd, argv, extra ->
          System.cmd(
            cmd,
            argv,
            Keyword.merge([into: IO.stream(:stdio, :line), stderr_to_stdout: true], extra)
          )
        end

    case runner.(command, args, command_opts) do
      {_, 0} -> :ok
      {_, status} -> Mix.raise("#{Path.basename(command)} failed with exit status #{status}")
    end
  end
end
