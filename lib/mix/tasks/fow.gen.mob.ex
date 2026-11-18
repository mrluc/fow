defmodule Mix.Tasks.Fow.Gen.Mob do
  @moduledoc false
  use Mix.Task

  alias Mix.Tasks.Fow.Gen.Mobile

  def run(args), do: Mobile.run(args)
end
