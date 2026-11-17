defmodule Mix.Tasks.Fow.Install.OsxLocal do
  use Mix.Task
  @shortdoc "Install a macOS app in Applications and register it with Spotlight"
  @moduledoc """
  Install an existing macOS .app and register it with Spotlight.

      mix fow.install.desktop --app "/path/to/My App.app"

  Use this after building separately, or use `mix fow.desktop` for the complete workflow. The default destination is ~/Applications. Pass `--applications DIR` to choose another directory or `--force` to replace an installed copy.

  ## How it fits

  This is the install step used by `mix fow.desktop`. Both call `FogOfWar.Wrapper.Workflow.install_osx_local!/2` directly. Use it separately when you already have a built app.
  """
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [app: :string, applications: :string, force: :boolean])

    if rest != [] || invalid != [] || !opts[:app],
      do: Mix.raise("Pass --app path/to/App.app, optionally --force and --applications path")

    destination = FogOfWar.Wrapper.Workflow.install_osx_local!(opts[:app], opts)
    Mix.shell().info("Installed #{destination}; registered with LaunchServices and Spotlight")
  end
end

# Mix normally maps OsxLocal to osx_local. Keep that conventional spelling and
# also provide the explicitly named installation strategy used by the public CLI.
defmodule :"Elixir.Mix.Tasks.Fow.Install.Osx-local" do
  use Mix.Task
  @shortdoc "Install a macOS app and register it with Spotlight"
  @moduledoc """
  Install an existing macOS .app and register it with Spotlight.

      mix fow.install.desktop --app "/path/to/My App.app"

  Use this after building separately, or use `mix fow.desktop` for the complete workflow. The default destination is ~/Applications. Pass `--applications DIR` to choose another directory or `--force` to replace an installed copy.

  ## How it fits

  This is the install step used by `mix fow.desktop`. Both call `FogOfWar.Wrapper.Workflow.install_osx_local!/2` directly. Use it separately when you already have a built app.
  """
  defdelegate run(args), to: Mix.Tasks.Fow.Install.OsxLocal
end
