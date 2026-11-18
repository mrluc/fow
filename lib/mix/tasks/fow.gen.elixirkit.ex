defmodule Mix.Tasks.Fow.Gen.Elixirkit do
  @moduledoc false
  use Mix.Task

  def run(args), do: Mix.Tasks.Fow.Gen.Desktop.run(args)
end
