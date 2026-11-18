defmodule Mix.Tasks.Fow.Gen.Mob do
  @moduledoc false
  use Mix.Task

  def run(args), do: Mix.Tasks.Fow.Gen.Mobile.run(args)
end
