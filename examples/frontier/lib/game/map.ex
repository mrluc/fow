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

  def view(id, square, table \\ :frontier_game) do
    case lookup(table, :view_clock) do
      {revision, tick, paused} ->
        player = lookup(table, {:player, id})
        entities = lookup(table, {:square, square}) || []

        # Several publications can share one game tick.
        case lookup(table, :view_clock) do
          {^revision, _, _} ->
            %{player: player, tick: tick, paused: paused, entities: without_player(entities, id)}

          _ ->
            view(id, square, table)
        end

      nil ->
        %{player: nil, tick: 0, paused: false, entities: []}
    end
  rescue
    ArgumentError -> %{player: nil, tick: 0, paused: false, entities: []}
  end

  def square_entities(game) do
    monster = game.monster

    squares =
      Enum.reduce(game.players, %{monster.position => [monster_entity(monster)]}, fn
        {id, %{health: health, position: square}}, acc when health > 0 ->
          entity = player_entity(id, health)
          Map.update(acc, square, [entity], &[entity | &1])

        _, acc ->
          acc
      end)

    for lat <- 0..3, lon <- 0..3 do
      square = {lat, lon}
      {square, Enum.sort_by(Map.get(squares, square, []), & &1.id)}
    end
  end

  def entities(state, position, except_player) do
    players =
      for {id, player} <- state.players,
          id != except_player and player.position == position and player.health > 0,
          do: player_entity(id, player.health)

    monster = state.monster

    entities =
      if monster.position == position, do: [monster_entity(monster) | players], else: players

    Enum.sort_by(entities, & &1.id)
  end

  defp player_entity(id, health), do: %{id: "player-" <> id, kind: :player, health: health}

  defp monster_entity(monster) do
    %{
      id: "monster-" <> monster.id,
      kind: :monster,
      mode: monster.mode,
      health: Map.get(monster, :health, FogOfWarFrontier.Game.Rules.monster_health())
    }
  end

  defp without_player(entities, nil), do: entities

  defp without_player(entities, id) do
    entity_id = "player-" <> id
    Enum.reject(entities, &(&1.id == entity_id))
  end

  defp lookup(table, key), do: :ets.lookup_element(table, key, 2, nil)

  def occupants(position) do
    snapshot().players
    |> Map.values()
    |> Enum.filter(&(&1.position == position))
    |> Enum.sort_by(& &1.id)
  end
end
