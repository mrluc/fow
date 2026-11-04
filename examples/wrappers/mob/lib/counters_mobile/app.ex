defmodule CountersMobile.App do
  use Mob.App
  def navigation(_platform), do: stack(:main, root: CountersMobile.FrontierScreen)

  def on_start do
    Mob.DNS.configure_pure_beam()
    {:ok, _} = Application.ensure_all_started(:bandit)
    # Mob owns the application supervisor; link this small public server to its app process.
    case CountersMobile.PublicShell.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Mob.Screen.start_root(CountersMobile.FrontierScreen)
    Mob.Dist.ensure_started(node: :"counters_mobile_android@127.0.0.1")
  end
end
