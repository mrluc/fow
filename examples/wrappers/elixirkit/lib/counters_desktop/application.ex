defmodule CountersDesktop.Application do
  use Application
  def start(_, _) do
    Supervisor.start_link([
      CountersDesktop.PublicShell,
      {ElixirKit.PubSub, connect: System.get_env("ELIXIRKIT_PUBSUB") || :ignore, on_exit: &System.stop/0},
      {Task, fn ->
        if System.get_env("ELIXIRKIT_PUBSUB"), do:
          ElixirKit.PubSub.broadcast("desktop", "ready:" <> CountersDesktop.PublicShell.url())
      end}
    ], strategy: :one_for_one, name: CountersDesktop.Supervisor)
  end
end
