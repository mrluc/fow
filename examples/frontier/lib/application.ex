defmodule FogOfWarFrontier.Application do
  use Application

  def start(_, _) do
    Supervisor.start_link(
      [
        {Phoenix.PubSub, name: FogOfWarFrontier.PubSub},
        FogOfWarFrontierWeb.Endpoint
      ], strategy: :one_for_one, name: FogOfWarFrontier.Supervisor)
  end

  def config_change(changed, _, removed),
    do: FogOfWarFrontierWeb.Endpoint.config_change(changed, removed)
end
