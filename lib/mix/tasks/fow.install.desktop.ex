defmodule Mix.Tasks.Fow.Install.Desktop do
  @shortdoc "Install a built macOS app"
  @moduledoc """
  Install an existing app and register it with Spotlight.

      mix fow.install.desktop --app "/path/to/My App.app"

  The default destination is ~/Applications. Use `--applications DIR` to
  choose a different directory and `--force` to replace the installed copy.
  For preparation through installation in one step, use `mix fow.desktop`.
  """
  use Mix.Task

  alias Mix.Tasks.Fow.Install.OsxLocal

  def run(args), do: OsxLocal.run(args)
end
