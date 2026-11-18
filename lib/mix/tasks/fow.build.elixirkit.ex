defmodule Mix.Tasks.Fow.Build.Elixirkit do
  @moduledoc false
  use Mix.Task

  def run(args), do: Mix.Tasks.Fow.Build.Desktop.run(args)
end
