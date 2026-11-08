defmodule FogOfWarFrontier.Game do
  @moduledoc "Runs the rule engine, checkpointing state and view ownership independently of its process."
  use GenServer
  alias FogOfWarFrontier.Game.{State, Cache}

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def observe(id, view, position), do: observe(__MODULE__, id, view, position)

  def observe(server, id, view, position),
    do: GenServer.cast(server, {:observe, id, view, position})

  def observe_sync(server, id, view, position),
    do: GenServer.call(server, {:observe, id, view, position})

  def act(server \\ __MODULE__, action), do: GenServer.call(server, {:act, action})
  def step(server \\ __MODULE__, actions \\ []), do: GenServer.call(server, {:step, actions})
  def reset(server \\ __MODULE__), do: GenServer.call(server, :reset)
  def snapshot(server \\ __MODULE__), do: GenServer.call(server, :snapshot)
  def pause(server \\ __MODULE__), do: GenServer.call(server, {:paused, true})
  def resume(server \\ __MODULE__), do: GenServer.call(server, {:paused, false})
  def topic(server), do: "frontier:game:#{inspect(server)}"

  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    cache = Keyword.get(opts, :cache, if(name == __MODULE__, do: Cache))

    {table, checkpoint} =
      if cache,
        do: Cache.restore(cache),
        else: {:ets.new(:frontier_game_test, [:set, :protected]), nil}

    {game, owners} = checkpoint || {State.new(Keyword.get_lazy(opts, :seed, &random_seed/0)), []}

    game = Map.put_new(game, :paused, false)

    {game, views} =
      Enum.reduce(owners, {game, %{}}, fn {id, pid}, {game, views} ->
        if Process.alive?(pid) do
          {game, Map.put(views, Process.monitor(pid), {id, pid})}
        else
          {State.dispatch(game, {:disconnect, id}), views}
        end
      end)

    state = %{
      game: game,
      views: views,
      name: name,
      table: table,
      cache: cache,
      automatic: Keyword.get(opts, :automatic, true)
    }

    publish(state)
    start_clock(state)
    {:ok, state}
  end

  def handle_cast({:observe, id, view, position}, state) do
    state = observe_view(state, id, view, position)
    {:noreply, state}
  end

  def handle_call({:observe, id, view, position}, _, state) do
    state = observe_view(state, id, view, position)
    {:reply, state.game, state}
  end

  def handle_call(:reset, _, state) do
    state = %{state | game: State.reset(state.game, random_seed())}
    publish(state)
    {:reply, state.game, state}
  end

  def handle_call({:paused, paused}, _, state) do
    state = %{state | game: Map.put(state.game, :paused, paused)}
    publish(state)
    {:reply, state.game, state}
  end

  def handle_call(:snapshot, _, state), do: {:reply, state.game, state}

  def handle_call({:act, action}, _, state) do
    state = %{state | game: State.dispatch(state.game, action)}
    publish(state)
    {:reply, state.game, state}
  end

  def handle_call({:step, actions}, _, state) do
    state = %{state | game: State.step(state.game, actions)}
    publish(state)
    {:reply, state.game, state}
  end

  def handle_info(:tick, %{game: %{paused: true}} = state), do: {:noreply, state}

  def handle_info(:tick, state) do
    state = %{state | game: State.step(state.game)}
    publish(state)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _, _}, state) do
    case Map.pop(state.views, ref) do
      {nil, _} ->
        {:noreply, state}

      {{id, _}, views} ->
        state = %{state | views: views, game: State.dispatch(state.game, {:disconnect, id})}
        publish(state)
        {:noreply, state}
    end
  end

  defp observe_view(state, id, view, position) do
    known = Enum.any?(state.views, fn {_, owner} -> owner == {id, view} end)

    state =
      if known do
        state
      else
        %{
          state
          | views: Map.put(state.views, Process.monitor(view), {id, view}),
            game: State.dispatch(state.game, {:connect, id, position})
        }
      end

    state =
      if known,
        do: %{state | game: State.dispatch(state.game, {:move, id, position})},
        else: state

    [event | rest] = state.game.recent
    event = Map.merge(event, %{requested: position, accepted: state.game.players[id].position})
    state = %{state | game: %{state.game | recent: [event | rest]}}
    publish(state)
    state
  end

  defp random_seed do
    <<a::64, b::64, c::64>> = :crypto.strong_rand_bytes(24)
    {a, b, c}
  end

  defp start_clock(%{automatic: true}) do
    {:ok, _timer} = :timer.send_interval(FogOfWarFrontier.Game.Rules.tick_ms(), self(), :tick)
    :ok
  end

  defp start_clock(_), do: :ok

  defp publish(state) do
    owners = Map.values(state.views)

    if state.cache,
      do: Cache.commit(state.cache, state.game, owners),
      else: Cache.write(state.table, state.game, owners)

    Phoenix.PubSub.broadcast(
      FogOfWarFrontier.PubSub,
      topic(state.name),
      {:game_tick, state.name, state.game.tick}
    )
  end
end
