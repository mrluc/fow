defmodule FogOfWarFrontier.Game.State do
  @moduledoc "Deterministic game state. No processes, ETS or wall-clock reads."
  alias FogOfWarFrontier.Game.{Player, Rules}

  defstruct tick: 0,
            paused: false,
            players: %{},
            recent: [],
            random: nil,
            monster: %{
              id: "split-brain",
              position: {3, 3},
              last_move_tick: 0,
              mode: :idle,
              health: Rules.monster_health(),
              respawn_tick: nil,
              decision_tick: 0
            }

  def new(seed \\ {1, 2, 3}), do: %__MODULE__{random: :rand.seed_s(:exsss, seed)}

  def reset(state, seed) do
    Enum.reduce(Enum.sort(state.players), %{new(seed) | paused: state.paused}, fn {id, previous},
                                                                                  game ->
      {square, random} = :rand.uniform_s(16, game.random)
      position = {div(square - 1, 4), rem(square - 1, 4)}

      player = %{
        Player.new(id, position, 0)
        | explored: 0,
          life: previous.life + 1,
          connected_views: previous.connected_views,
          last_offline_tick: if(previous.connected_views == 0, do: 0, else: nil)
      }

      put(%{game | random: random}, player, :game_reset)
    end)
  end

  def dispatch(%{paused: true} = state, {:move, id, _}),
    do: reject(state, id, :move, :paused)

  def dispatch(%{paused: true} = state, {:attack, id, _}),
    do: reject(state, id, :attack, :paused)

  def dispatch(state, {:connect, id, position}) do
    player =
      case Map.get(state.players, id) do
        nil -> nil
        player -> Player.with_preloads(player)
      end

    cond do
      not Player.valid_position?(position) ->
        reject(state, id, :connect, :outside_map)

      is_nil(player) ->
        player = %{Player.new(id, position, state.tick) | connected_views: 1}
        put(state, player, :connected)

      player.connected_views == 0 ->
        result =
          Player.reconnect(
            player,
            if(state.paused, do: player.position, else: position),
            state.tick
          )

        player = %{player | connected_views: 1, last_online_tick: state.tick}
        state = put(state, player, :connected)
        apply_result(state, id, :reconnect, result) |> clear_departure(id)

      true ->
        result =
          Player.reconnect(
            player,
            if(state.paused, do: player.position, else: position),
            state.tick
          )

        state = put(state, %{player | connected_views: player.connected_views + 1}, :connected)
        apply_result(state, id, :reconnect, result) |> clear_departure(id)
    end
  end

  def dispatch(state, {:disconnect, id}) do
    case state.players[id] do
      nil ->
        state

      player ->
        count = max(0, player.connected_views - 1)

        player =
          if player.connected_views > 0,
            do: Map.put(player, :last_disconnect_tick, state.tick),
            else: player

        put(
          state,
          %{
            player
            | connected_views: count,
              last_offline_tick:
                if(count == 0 and player.connected_views > 0,
                  do: state.tick,
                  else: player.last_offline_tick
                )
          },
          :disconnected
        )
    end
  end

  def dispatch(state, {:move, id, position}) do
    case state.players[id] do
      nil -> reject(state, id, :move, :unknown_player)
      player -> apply_result(state, id, :move, Player.move(player, position, state.tick))
    end
  end

  def dispatch(state, {:attack, id, :monster}) do
    target = Map.put_new(state.monster, :health, Rules.monster_health())

    with %Player{} = player <- state.players[id],
         {:ok, attacker} <- Player.prepare_attack(player, target, state.tick) do
      health = max(0, target.health - Rules.attack_damage())
      defeated = health == 0

      monster =
        if defeated do
          Map.merge(target, %{
            health: 0,
            mode: :banished,
            respawn_tick: state.tick + Rules.monster_respawn_ticks()
          })
        else
          %{target | health: health}
        end

      attacker =
        if defeated,
          do: Player.record_kill(%{attacker | lives: attacker.lives + 1}, :monster_kills),
          else: attacker

      %{state | monster: monster, players: Map.put(state.players, id, attacker)}
      |> event(%{
        player: id,
        action: :attack,
        target: :monster,
        result: :ok,
        position: player.position,
        defeated: defeated
      })
    else
      {:error, reason} -> reject(state, id, :attack, reason)
      nil -> reject(state, id, :attack, :unknown_player)
    end
  end

  def dispatch(state, {:attack, id, target_id}) do
    with %Player{} = player <- state.players[id],
         %Player{} = target <- state.players[target_id],
         {:ok, attacker, target} <- Player.attack(player, target, state.tick) do
      state |> put(attacker, :attack) |> put(target, :hit)
    else
      {:error, reason} -> reject(state, id, :attack, reason)
      nil -> reject(state, id, :attack, :unknown_player)
    end
  end

  def step(state, actions \\ []) do
    state = %{state | tick: state.tick + 1}
    state = Enum.reduce(actions, state, &dispatch(&2, &1))

    state =
      Enum.reduce(Enum.sort(Map.keys(state.players)), state, fn id, acc ->
        player = acc.players[id]

        if Player.expired?(player, acc.tick) do
          %{acc | players: Map.delete(acc.players, id)}
        else
          advance_player(acc, Player.tick(player, acc.tick))
        end
      end)

    walk_monster(state)
  end

  if Mix.env() == :test do
    defp walk_monster(%{monster: %{mode: :disabled}} = state), do: state
  end

  defp walk_monster(%{monster: %{mode: :banished, respawn_tick: ready}} = state) do
    if state.tick >= ready do
      {lat, lon} = state.monster.position
      {offset, random} = :rand.uniform_s(15, state.random)
      square = rem(lat * 4 + lon + offset, 16)

      monster = %{
        state.monster
        | position: {div(square, 4), rem(square, 4)},
          health: Rules.monster_health(),
          mode: :idle,
          last_move_tick: state.tick,
          decision_tick: state.tick,
          respawn_tick: nil
      }

      event(%{state | monster: monster, random: random}, %{action: :monster_respawn, result: :ok})
    else
      state
    end
  end

  defp walk_monster(state) do
    if rem(state.tick, Rules.monster_move_ticks()) == 0 do
      occupied =
        Enum.any?(state.players, fn {_, player} ->
          player.position == state.monster.position and player.health > 0 and
            player.connected_views > 0
        end)

      if occupied do
        monster = %{state.monster | mode: :exploding, decision_tick: state.tick}

        state =
          Enum.reduce(Enum.sort(Map.keys(state.players)), state, fn id, acc ->
            player = acc.players[id]

            if player.position == monster.position and player.health > 0 and
                 player.connected_views > 0 do
              put(acc, Player.damage(player, Rules.monster_damage(), state.tick), :monster_hit)
            else
              acc
            end
          end)

        event(%{state | monster: monster}, %{action: :monster_explode, result: :ok})
      else
        {lat, lon} = state.monster.position
        neighbors = for y <- 0..3, x <- 0..3, max(abs(y - lat), abs(x - lon)) == 1, do: {y, x}
        {choice, random} = :rand.uniform_s(length(neighbors), state.random)

        monster = %{
          state.monster
          | position: Enum.at(neighbors, choice - 1),
            last_move_tick: state.tick,
            mode: :idle,
            decision_tick: state.tick
        }

        event(%{state | monster: monster, random: random}, %{action: :monster_move, result: :ok})
      end
    else
      state
    end
  end

  defp advance_player(acc, player) do
    id = player.id

    if player.death_tick && acc.tick >= player.death_tick + Rules.respawn_ticks() do
      {square, random} = :rand.uniform_s(16, acc.random)
      position = {div(square - 1, 4), rem(square - 1, 4)}

      respawn = %{
        Player.new(id, position, acc.tick)
        | lives: player.lives,
          life: player.life + 1,
          connected_views: player.connected_views,
          explored: 0,
          last_offline_tick: player.last_offline_tick
      }

      put(%{acc | random: random}, respawn, :respawn)
    else
      %{acc | players: Map.put(acc.players, id, player)}
    end
  end

  defp clear_departure(state, id) do
    update_in(state.players[id], &Map.put(&1, :last_disconnect_tick, nil))
  end

  defp apply_result(state, id, action, {:error, reason}), do: reject(state, id, action, reason)

  defp apply_result(state, id, action, {:ok, player}) do
    # Preserve connection bookkeeping updated before a reconnect result is applied.
    player = %{
      player
      | connected_views: state.players[id].connected_views,
        last_online_tick: state.players[id].last_online_tick
    }

    put(state, player, action)
  end

  defp put(state, player, action) do
    state = %{state | players: Map.put(state.players, player.id, player)}
    event(state, %{player: player.id, action: action, result: :ok})
  end

  defp reject(state, id, action, reason),
    do: event(state, %{player: id, action: action, result: reason})

  defp event(state, event),
    do: %{state | recent: Enum.take([Map.put(event, :tick, state.tick) | state.recent], 30)}
end
