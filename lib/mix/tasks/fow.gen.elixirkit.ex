defmodule Mix.Tasks.Fow.Gen.Elixirkit do
  use Mix.Task
  @moduledoc false
  def run(args), do: Mix.Tasks.Fow.Gen.Desktop.run(args)
end
