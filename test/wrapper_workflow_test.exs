defmodule FogOfWar.WrapperWorkflowTest do
  use ExUnit.Case, async: false

  alias FogOfWar.Wrapper.Generator
  alias FogOfWar.Wrapper.Manifest
  alias FogOfWar.Wrapper.NativeBundle
  alias FogOfWar.Wrapper.Output
  alias FogOfWar.Wrapper.Workflow

  setup do
    root = Path.join(System.tmp_dir!(), "fow-workflow-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    manifest = %{
      "schema" => 3,
      "app" => %{
        "name" => "Sample",
        "slug" => "sample",
        "identifier" => "dev.test.sample",
        "version" => "0.1.0"
      },
      "web" => %{"origin" => "https://example.com"},
      "startup" => %{"path" => "/"},
      "preload" => %{"paths" => []},
      "assets" => %{"directories" => []},
      "mob" => %{"platforms" => ["android"]},
      "elixirkit" => %{"width" => 800, "height" => 600}
    }

    path = Path.join(root, ".fow.json")
    Manifest.write!(path, manifest)
    %{root: root, manifest: Manifest.resolve!(manifest), path: path}
  end

  defp html(_url),
    do:
      ~s(<html><head><title>Public</title></head><body><main id="page" phx-hook="FogOfWar" data-fog-of-war-path="/">Public</main></body></html>)

  test "all public task spellings resolve, including the hyphenated install strategy" do
    for name <- [
          "fow.desktop",
          "fow.build.elixirkit",
          "fow.install.osx-local",
          "fow.install.osx_local"
        ] do
      assert Mix.Task.get(name)
    end
  end

  test "force replaces a complete generated project only after generation succeeds", %{
    root: root,
    manifest: manifest,
    path: path
  } do
    NativeBundle.run!(manifest, root, Path.join(root, ".fow/default/bundles/apple"), "apple", fetch: &html/1)

    output = Path.join(root, "desktop")
    Generator.run!(:elixirkit, path, output)
    File.write!(Path.join(output, "custom.txt"), "user edit")

    assert_raise Mix.Error, ~r/Destination exists/, fn ->
      Generator.run!(:elixirkit, path, output)
    end

    bad = put_in(manifest, ["app", "icon"], "missing.png")
    Manifest.write!(path, bad, true)
    assert_raise File.Error, fn -> Generator.run!(:elixirkit, path, output, force: true) end
    assert File.read!(Path.join(output, "custom.txt")) == "user edit"
    Manifest.write!(path, manifest, true)
    Generator.run!(:elixirkit, path, output, force: true)
    refute File.exists?(Path.join(output, "custom.txt"))
    assert File.regular?(Path.join(output, "mix.exs"))
    assert Path.wildcard(output <> ".tmp-*") == []
    assert Path.wildcard(output <> ".old-*") == []
  end

  test "staged writes reject paths outside the staging directory", %{root: root} do
    stage = Path.join(root, "stage")
    outside = Path.join(root, "outside.txt")

    for path <- ["../outside.txt", outside] do
      assert_raise Mix.Error, ~r/project-relative path/, fn ->
        Output.write_staged!(stage, path, "content")
      end
    end

    refute File.exists?(outside)
    refute File.exists?(stage)
    assert :ok = Output.write_staged!(stage, "nested/inside.txt", "content")
    assert File.read!(Path.join(stage, "nested/inside.txt")) == "content"
  end

  test "replacement rejects source, ancestors, home and symlink destinations", %{root: root} do
    for output <- ["/", System.user_home!(), root, Path.dirname(root)] do
      assert_raise Mix.Error, ~r/protected/, fn ->
        Output.replace!(output, [force: true, protected: [root]], fn _ ->
          flunk("must reject before writing")
        end)
      end
    end

    target = Path.join(root, "real")
    File.mkdir!(target)
    File.write!(Path.join(target, "keep"), "safe")
    alias_path = Path.join(root, "alias")
    File.ln_s!(target, alias_path)

    for path <- [alias_path, Path.join(alias_path, "child")] do
      assert_raise Mix.Error, ~r/symlink/, fn ->
        Output.replace!(path, [force: true], fn _ -> flunk("must reject before writing") end)
      end
    end

    assert File.read!(Path.join(target, "keep")) == "safe"
  end

  test "build executes the generated script and finds the native artifact", %{
    root: root,
    manifest: manifest,
    path: path
  } do
    NativeBundle.run!(manifest, root, Path.join(root, ".fow/default/bundles/apple"), "apple", fetch: &html/1)

    output = Path.join(root, "desktop")
    Generator.run!(:elixirkit, path, output)
    target = Path.join(root, "native-target")
    app = Path.join(target, "release/bundle/macos/Sample.app")

    runner = fn command, args, opts ->
      assert command == "bash"
      assert args == ["build.sh"]
      assert opts[:cd] == output
      File.mkdir_p!(Path.join(app, "Contents"))
      File.write!(Path.join(app, "Contents/Info.plist"), "plist")
      {"", 0}
    end

    assert Workflow.build_elixirkit!(output, runner: runner, target_dir: target) == app

    assert_raise Mix.Error, ~r/exit status 9/, fn ->
      Workflow.build_elixirkit!(output, runner: fn _, _, _ -> {"failed", 9} end)
    end
  end

  test "installer copies atomically and registers the installed path without launching", %{
    root: root
  } do
    source = Path.join(root, "build/Sample.app")
    File.mkdir_p!(Path.join(source, "Contents"))
    File.write!(Path.join(source, "Contents/Info.plist"), "plist")
    applications = Path.join(root, "Applications")

    runner = fn command, args, _opts ->
      send(self(), {:command, command, args})

      if command == "/usr/bin/ditto" do
        [from, to] = args
        File.cp_r!(from, to)
      end

      {"", 0}
    end

    destination =
      Workflow.install_osx_local!(source,
        applications: applications,
        runner: runner,
        os: {:unix, :darwin}
      )

    assert destination == Path.join(applications, "Sample.app")
    assert File.read!(Path.join(destination, "Contents/Info.plist")) == "plist"
    assert_receive {:command, "/usr/bin/ditto", _}
    assert_receive {:command, registration, ["-f", ^destination]}
    assert String.ends_with?(registration, "/lsregister")
    assert_receive {:command, "/usr/bin/mdimport", [^destination]}
    refute_receive {:command, "/usr/bin/open", _}

    assert_raise Mix.Error, ~r/Destination exists/, fn ->
      Workflow.install_osx_local!(source,
        applications: applications,
        runner: runner,
        os: {:unix, :darwin}
      )
    end

    failed = fn _, _, _ -> {"copy failed", 1} end

    assert_raise Mix.Error, ~r/exit status 1/, fn ->
      Workflow.install_osx_local!(source,
        applications: applications,
        runner: failed,
        force: true,
        os: {:unix, :darwin}
      )
    end

    assert File.read!(Path.join(destination, "Contents/Info.plist")) == "plist"

    assert_raise Mix.Error, ~r/requires macOS/, fn ->
      Workflow.install_osx_local!(source, os: {:unix, :linux})
    end
  end

  test "desktop convenience prepares the Apple bundle, generates, builds and installs", %{
    root: root,
    path: path
  } do
    project = Path.join(root, "desktop")
    target = Path.join(root, "native-target")
    app = Path.join(target, "release/bundle/macos/Sample.app")

    runner = fn command, args, opts ->
      case command do
        "bash" ->
          assert opts[:cd] == project
          bundle = Path.join(project, "priv/fog_of_war/apple")

          assert Jason.decode!(File.read!(Path.join(bundle, "native.json")))["platform"] ==
                   "apple"

          assert File.read!(Path.join(bundle, "startup.html")) =~ "window.__fogOfWarNativeBundle="
          assert File.read!(Path.join(project, "src-tauri/src/main.rs")) =~ "loadSimulatedRequest"
          File.mkdir_p!(Path.join(app, "Contents"))
          File.write!(Path.join(app, "Contents/Info.plist"), "plist")

        "/usr/bin/ditto" ->
          [from, to] = args
          File.cp_r!(from, to)

        _ ->
          :ok
      end

      {"", 0}
    end

    opts = [
      output: project,
      applications: Path.join(root, "Applications"),
      target_dir: target,
      runner: runner,
      fetch: &html/1,
      os: {:unix, :darwin}
    ]

    installed = Workflow.desktop!(path, opts)
    assert File.regular?(Path.join(installed, "Contents/Info.plist"))
    File.write!(Path.join(project, "custom.txt"), "discard")
    assert Workflow.desktop!(path, Keyword.put(opts, :force, true)) == installed
    refute File.exists?(Path.join(project, "custom.txt"))
  end
end
