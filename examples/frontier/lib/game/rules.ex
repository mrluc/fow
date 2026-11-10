defmodule FogOfWarFrontier.Game.Rules do
  @moduledoc "Shared rule parameters for the engine and client presentation."
  def tick_ms, do: 100
  def connection_recovery_multiplier, do: 2
  def monster_move_ticks, do: 30
  def monster_damage, do: 49
  def monster_health, do: 200
  def monster_respawn_ticks, do: 60
  def attack_cost, do: 20
  def attack_damage, do: 100
  def health_max, do: 100
  def initial_lives, do: 3
  def preloaded_squares, do: [{0, 0}, {0, 1}, {1, 0}, {1, 1}]
  def respawn_ticks, do: 50
  def move_recharge_ms, do: 1000
  def offline_threshold, do: 10
  def offline_fast_damage, do: 10
  def offline_slow_damage, do: 1
  def healing_per_second, do: 10
  def moving_healing_per_second, do: 5
  def move_ticks, do: div(move_recharge_ms(), tick_ms())

  def client do
    %{
      tick_ms: tick_ms(),
      initial_lives: initial_lives(),
      preloaded_squares: Enum.map(preloaded_squares(), &Tuple.to_list/1),
      respawn_delay_ms: respawn_ticks() * tick_ms(),
      connection_recovery_multiplier: connection_recovery_multiplier(),
      health_max: health_max(),
      attack_cost: attack_cost(),
      move_recharge_ms: move_recharge_ms(),
      offline_threshold: offline_threshold(),
      offline_fast_damage: offline_fast_damage(),
      offline_slow_damage: offline_slow_damage(),
      healing_per_second: healing_per_second(),
      moving_healing_per_second: moving_healing_per_second()
    }
  end
end
