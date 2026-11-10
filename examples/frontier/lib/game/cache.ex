defmodule FogOfWarFrontier.Game.Cache do
  @moduledoc "Owns the in-memory game checkpoint independently of the Game process."
  use GenServer

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def restore(server), do: GenServer.call(server, :restore)
  def commit(server, game, views), do: GenServer.call(server, {:commit, game, views})

  def init(opts) do
    table =
      case Keyword.get(opts, :table, :frontier_game) do
        :anonymous -> :ets.new(:frontier_game, [:set, :protected, read_concurrency: true])
        name -> :ets.new(name, [:named_table, :set, :protected, read_concurrency: true])
      end

    {:ok, table}
  end

  def handle_call(:restore, _, table) do
    checkpoint =
      case :ets.lookup(table, :snapshot) do
        [{:snapshot, game}] ->
          [{:views, views}] = :ets.lookup(table, :views)
          {game, views}

        [] ->
          nil
      end

    {:reply, {table, checkpoint}, table}
  end

  def handle_call({:commit, game, views}, _, table) do
    write(table, game, views)
    {:reply, :ok, table}
  end

  @doc false
  def write(table, game, views) do
    previous_ids =
      case :ets.lookup(table, :player_ids) do
        [{:player_ids, ids}] -> ids
        [] -> previous_player_ids(table)
      end

    ids = MapSet.new(Map.keys(game.players))
    removed = MapSet.difference(previous_ids, ids)
    revision = System.unique_integer([:monotonic, :positive])
    players = Enum.map(game.players, fn {id, player} -> {{:player, id}, player} end)

    squares =
      for {square, entities} <- FogOfWarFrontier.Game.Map.square_entities(game),
          do: {{:square, square}, entities}

    # Tombstones make removals visible in the same atomic insert as the new revision.
    tombstones = for id <- removed, do: {{:player, id}, nil}

    :ets.insert(table, [
      {:snapshot, game},
      {:views, views},
      {:player_ids, ids},
      {:view_clock, {revision, game.tick, Map.get(game, :paused, false)}}
      | players ++ squares ++ tombstones
    ])

    Enum.each(removed, &:ets.delete(table, {:player, &1}))
  end

  defp previous_player_ids(table) do
    case :ets.lookup(table, :snapshot) do
      [{:snapshot, game}] -> MapSet.new(Map.keys(game.players))
      [] -> MapSet.new()
    end
  end
end
