defmodule Mix.Tasks.Fow.Gen.Mob do
  use Mix.Task
  @moduledoc false
  def run(args), do: Mix.Tasks.Fow.Gen.Mobile.run(args)
end
