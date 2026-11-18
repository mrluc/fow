defmodule Mix.Tasks.Fow.Build.Elixirkit do
  @moduledoc false
  use Mix.Task

  alias Mix.Tasks.Fow.Build.Desktop

  def run(args), do: Desktop.run(args)
end
