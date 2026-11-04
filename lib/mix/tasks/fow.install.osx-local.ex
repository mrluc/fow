defmodule Mix.Tasks.Fow.Install.OsxLocal do
  use Mix.Task
  @shortdoc "Install a macOS app in Applications and register it with Spotlight"
  @moduledoc "Run `mix fow.install.osx-local --app path/to/App.app [--force] [--applications path]`."
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
  @moduledoc "Alias for `mix fow.install.osx_local`; accepts --app, --applications and --force."
  defdelegate run(args), to: Mix.Tasks.Fow.Install.OsxLocal
end
