defmodule FogOfWarFrontier.Game.Map do
  @moduledoc "Direct, atomic ETS snapshot reads without calling the default game process."
  def trees({lat, lon}) do
    for {tree, present} <- [pine: rem(lat + lon, 3) != 0, second_pine: rem(lat * 3 + lon, 4) == 0],
        present,
        do: tree
  end

  def snapshot do
    case :ets.lookup(:frontier_game, :snapshot) do
      [{:snapshot, state}] -> state
      [] -> FogOfWarFrontier.Game.State.new()
    end
  rescue
    ArgumentError -> FogOfWarFrontier.Game.State.new()
  end

  def player(id) do
    case :ets.lookup(:frontier_game, {:player, id}) do
      [{_, player}] -> player
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def entities(state, position, except_player) do
    players =
      for {id, player} <- state.players,
          id != except_player and player.position == position and player.health > 0,
          do: %{id: "player-" <> id, kind: :player, health: player.health}

    monster =
      if state.monster.position == position,
        do: [%{id: "monster-" <> state.monster.id, kind: :monster, mode: state.monster.mode}],
        else: []

    Enum.sort_by(players ++ monster, & &1.id)
  end

  def occupants(position) do
    snapshot().players
    |> Map.values()
    |> Enum.filter(&(&1.position == position))
    |> Enum.sort_by(& &1.id)
  end
end
