defmodule Mix.Tasks.Fow.Install.Mobile do
  @shortdoc "Install an APK or simulator .app"
  @moduledoc """
  Install an existing artifact on Android or an iOS simulator.

      mix fow.install.mobile --app path/to/app.apk
      mix fow.install.mobile --app path/to/App.app --device booted

  Use `--device` to choose an adb serial or iOS simulator ID.
  """

  use Mix.Task

  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [app: :string, device: :string])

    if rest != [] || invalid != [] || !opts[:app],
      do: Mix.raise("Pass --app and optionally --device")

    app = Path.expand(opts[:app])

    {tool, arguments} =
      case Path.extname(app) do
        ".apk" ->
          if !File.regular?(app), do: Mix.raise("APK does not exist: #{app}")
          serial = if opts[:device], do: ["-s", opts[:device]], else: []
          {"adb", serial ++ ["install", "-r", app]}

        ".app" ->
          if !File.dir?(app), do: Mix.raise("App does not exist: #{app}")
          {"xcrun", ["simctl", "install", opts[:device] || "booted", app]}

        _ ->
          Mix.raise("Expected an Android APK or iOS simulator .app")
      end

    {_, status} =
      System.cmd(tool, arguments, into: IO.stream(:stdio, :line), stderr_to_stdout: true)

    if status != 0, do: Mix.raise("#{tool} exited with status #{status}")
  end
end
