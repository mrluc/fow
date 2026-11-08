defmodule FogOfWarFrontier.Game.Player do
  @moduledoc "Pure player rules evaluated using game ticks."
  import Bitwise
  alias FogOfWarFrontier.Game.Rules

  defstruct [
    :id,
    :position,
    :last_move_tick,
    :last_attack_tick,
    :last_online_tick,
    :last_offline_tick,
    :last_disconnect_tick,
    :death_tick,
    lives: Rules.initial_lives(),
    life: 0,
    health: Rules.health_max(),
    explored: 0,
    connected_views: 0,
    charge_ready_tick: 0
  ]

  def new(id, position, tick),
    do:
      with_preloads(%__MODULE__{
        id: id,
        position: position,
        explored: bit(position),
        last_online_tick: tick
      })

  def with_preloads(player) do
    Enum.reduce(Rules.preloaded_squares(), player, fn position, player ->
      %{player | explored: player.explored ||| bit(position)}
    end)
  end

  def valid_position?({lat, lon}), do: lat in 0..3 and lon in 0..3
  def valid_position?(_), do: false
  def distance({a, b}, {c, d}), do: max(abs(a - c), abs(b - d))

  def explored?(player, position),
    do: valid_position?(position) and (player.explored &&& bit(position)) != 0

  def ready?(player, tick), do: player.health > 0 and tick >= player.charge_ready_tick

  def expired?(player, tick) do
    player.connected_views == 0 and is_integer(player.last_offline_tick) and
      tick - player.last_offline_tick >= 1200
  end

  def move(player, position, tick) do
    cond do
      player.connected_views == 0 ->
        {:error, :offline}

      player.health <= 0 ->
        {:error, :dead}

      position == player.position ->
        {:ok, %{player | explored: player.explored ||| bit(position)}}

      not valid_position?(position) ->
        {:error, :outside_map}

      distance(player.position, position) != 1 ->
        {:error, :not_adjacent}

      not ready?(player, tick) ->
        {:error, :recharging}

      true ->
        {:ok,
         %{
           player
           | position: position,
             last_move_tick: tick,
             charge_ready_tick: tick + Rules.move_ticks(),
             explored: player.explored ||| bit(position)
         }}
    end
  end

  def reconnect(player, position, tick) do
    departure =
      Map.get(player, :last_disconnect_tick) ||
        if(player.connected_views == 0, do: player.last_offline_tick || tick, else: tick)

    first_move_tick = max(departure, player.charge_ready_tick)

    budget =
      if tick >= first_move_tick,
        do: div(tick - first_move_tick, Rules.move_ticks()) + 1,
        else: 0

    cond do
      player.health <= 0 ->
        {:error, :dead}

      not explored?(player, position) ->
        {:error, :unexplored}

      distance(player.position, position) > budget ->
        {:error, :too_far}

      position == player.position ->
        {:ok, player}

      true ->
        {:ok,
         %{
           player
           | position: position,
             last_move_tick: tick,
             charge_ready_tick: tick + Rules.move_ticks()
         }}
    end
  end

  def attack(player, target, tick) do
    cond do
      player.connected_views == 0 ->
        {:error, :offline}

      not ready?(player, tick) ->
        {:error, :not_ready}

      player.id == target.id or target.health <= 0 ->
        {:error, :invalid_target}

      target.position != player.position ->
        {:error, :different_square}

      true ->
        attacker =
          damage(
            %{player | charge_ready_tick: tick + Rules.move_ticks(), last_attack_tick: tick},
            20,
            tick
          )

        {:ok, attacker, damage(target, 70, tick)}
    end
  end

  def damage(player, amount, tick) do
    health = max(0, player.health - amount)

    %{
      player
      | health: health,
        lives: if(health == 0 and player.health > 0, do: player.lives - 1, else: player.lives),
        death_tick: if(health == 0, do: player.death_tick || tick, else: nil)
    }
  end

  def tick(player, tick) do
    cond do
      player.health <= 0 ->
        player

      player.connected_views > 0 ->
        rate =
          if player.last_move_tick == tick,
            do: Rules.moving_healing_per_second(),
            else: Rules.healing_per_second()

        %{player | health: min(Rules.health_max(), player.health + rate * Rules.tick_ms() / 1000)}

      is_integer(player.last_offline_tick) and
          rem(tick - player.last_offline_tick, div(1000, Rules.tick_ms())) == 0 ->
        damage(
          player,
          if(player.health > Rules.offline_threshold(),
            do: min(Rules.offline_fast_damage(), player.health - Rules.offline_threshold()),
            else: Rules.offline_slow_damage()
          ),
          tick
        )

      true ->
        player
    end
  end

  defp bit({lat, lon}), do: 1 <<< (lat * 4 + lon)
end
