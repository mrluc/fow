defmodule Mix.Tasks.Fow.Gen.Elixirkit do
  @moduledoc false
  use Mix.Task

  alias Mix.Tasks.Fow.Gen.Desktop

  def run(args), do: Desktop.run(args)
end
