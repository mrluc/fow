defmodule Mix.Tasks.Fow.Build.Elixirkit do
  use Mix.Task
  @moduledoc false
  def run(args), do: Mix.Tasks.Fow.Build.Desktop.run(args)
end
