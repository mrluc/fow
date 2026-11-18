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
    {tool, arguments} = install_command!(Path.extname(app), app, opts[:device])

    {_, status} =
      System.cmd(tool, arguments, into: IO.stream(:stdio, :line), stderr_to_stdout: true)

    if status != 0, do: Mix.raise("#{tool} exited with status #{status}")
  end

  defp install_command!(".apk", app, device) do
    if !File.regular?(app), do: Mix.raise("APK does not exist: #{app}")
    serial = if device, do: ["-s", device], else: []
    {"adb", serial ++ ["install", "-r", app]}
  end

  defp install_command!(".app", app, device) do
    if !File.dir?(app), do: Mix.raise("App does not exist: #{app}")
    {"xcrun", ["simctl", "install", device || "booted", app]}
  end

  defp install_command!(_, _, _), do: Mix.raise("Expected an Android APK or iOS simulator .app")
end
