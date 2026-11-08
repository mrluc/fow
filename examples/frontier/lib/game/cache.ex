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
    previous =
      case :ets.lookup(table, :snapshot) do
        [{:snapshot, old}] -> old.players
        [] -> %{}
      end

    for id <- Map.keys(previous) -- Map.keys(game.players), do: :ets.delete(table, {:player, id})

    :ets.insert(table, [
      {:snapshot, game},
      {:views, views}
      | Enum.map(game.players, fn {id, player} -> {{:player, id}, player} end)
    ])
  end
end
