defmodule FogOfWarFrontier.GameStateTest do
  use ExUnit.Case, async: true
  alias FogOfWarFrontier.Game.{Player, State}

  defp connected do
    State.new() |> State.dispatch({:connect, "a", {0, 0}})
  end

  defp ticks(state, count), do: Enum.reduce(1..count, state, fn _, state -> State.step(state) end)

  test "movement enforces adjacency and recharge" do
    state = connected() |> State.dispatch({:move, "a", {0, 1}})
    assert state.players["a"].position == {0, 1}
    denied = State.dispatch(state, {:move, "a", {1, 1}})
    assert hd(denied.recent).result == :recharging
    state = state |> ticks(10) |> State.dispatch({:move, "a", {1, 1}})
    assert state.players["a"].position == {1, 1}
    assert hd(State.dispatch(state, {:move, "a", {3, 3}}).recent).result == :not_adjacent
  end

  test "offline death occurs at 19 seconds and respawn waits another five" do
    state = connected() |> State.dispatch({:disconnect, "a"}) |> ticks(90)
    assert state.players["a"].health == 10
    last_chance = ticks(state, 99)
    saved = State.dispatch(last_chance, {:connect, "a", {0, 0}})
    assert saved.players["a"].health == 1
    assert saved.players["a"].lives == 3
    assert saved.players["a"].death_tick == nil

    dead = ticks(state, 100)
    assert dead.players["a"].death_tick == 190
    assert dead.players["a"].health == 0
    assert State.dispatch(dead, {:connect, "a", {0, 0}}).players["a"].health == 0
    assert ticks(dead, 49).players["a"].health == 0
    respawn = ticks(dead, 50)
    assert respawn.players["a"].lives == 2
    assert respawn.players["a"].life == 1
    assert respawn.players["a"].health == 100
    assert respawn.players["a"].explored == 0
    assert Player.valid_position?(respawn.players["a"].position)
    assert ticks(dead, 50) == respawn
  end

  test "lives start at three, count each death once and can go negative" do
    player = Player.new("a", {0, 0}, 0)
    assert player.lives == 3

    player =
      Enum.reduce(1..5, player, fn tick, player ->
        killed = Player.damage(%{player | health: 100, death_tick: nil}, 100, tick)
        assert Player.damage(killed, 100, tick).lives == killed.lives
        killed
      end)

    assert player.lives == -2
  end

  test "an explosion hits every living occupant once, and leaves other squares alone" do
    state =
      State.new()
      |> State.dispatch({:connect, "a", {3, 3}})
      |> State.dispatch({:connect, "b", {3, 3}})
      |> State.dispatch({:connect, "safe", {0, 0}})

    before = ticks(state, 29)
    assert before.players["a"].health == 100
    exploded = State.step(before)
    assert exploded.players["a"].health == 100 - FogOfWarFrontier.Game.Rules.monster_damage()
    assert exploded.players["b"].health == exploded.players["a"].health
    assert exploded.players["safe"].health == 100
    next = State.step(exploded)
    assert next.players["a"].health > exploded.players["a"].health
    assert next.monster.decision_tick == exploded.monster.decision_tick
  end

  test "lethal explosions spend only one life per victim" do
    state =
      State.new()
      |> State.dispatch({:connect, "a", {3, 3}})
      |> State.dispatch({:connect, "b", {3, 3}})
      |> ticks(29)

    state = put_in(state.players["a"].health, 1)
    killed = State.step(state)
    assert killed.players["a"].health == 0
    assert killed.players["a"].lives == 2
    assert killed.players["a"].death_tick == 30
    again = ticks(killed, 30)
    assert again.players["a"].lives == 2
    assert again.players["a"].death_tick == 30
  end

  test "monster explodes in place while occupied and resumes walking after players leave" do
    state = State.new() |> State.dispatch({:connect, "a", {3, 3}}) |> ticks(30)
    assert state.monster.position == {3, 3}
    assert state.monster.mode == :exploding
    again = ticks(state, 30)
    assert again.monster.position == {3, 3}
    assert again.monster.decision_tick == 60
    assert again.monster.mode == :exploding
    left = again |> State.dispatch({:move, "a", {2, 2}}) |> ticks(30)
    assert left.monster.position != {3, 3}
    assert left.monster.mode == :idle
  end

  test "presenting a respawn square records exploration before a later reconnect" do
    state = connected() |> State.dispatch({:disconnect, "a"}) |> ticks(240)
    spawn = state.players["a"].position
    assert state.players["a"].explored == 0
    state = state |> State.dispatch({:connect, "a", spawn}) |> State.dispatch({:move, "a", spawn})
    assert Player.explored?(state.players["a"], spawn)
    state = state |> State.dispatch({:disconnect, "a"}) |> State.dispatch({:connect, "a", spawn})
    assert hd(state.recent).result == :ok
  end

  test "reset starts a fresh match while retaining player identities and connections" do
    state =
      connected()
      |> State.dispatch({:connect, "b", {1, 1}})
      |> State.dispatch({:disconnect, "b"})
      |> ticks(10)

    state = put_in(state.players["a"].lives, -2)
    reset = State.reset(state, {7, 8, 9})
    assert reset.tick == 0
    assert reset.monster.position == {3, 3}

    for {id, player} <- reset.players do
      assert player.health == 100
      assert player.lives == 3
      assert player.life == state.players[id].life + 1
      assert player.explored == 0
      assert Player.valid_position?(player.position)
      assert player.connected_views == state.players[id].connected_views
    end

    assert reset.players["b"].last_offline_tick == 0
    assert State.reset(state, {7, 8, 9}) == reset
  end

  test "healing rate is reduced only on a successful movement tick" do
    state = connected()
    state = put_in(state.players["a"].health, 50)
    state = State.step(state, [{:move, "a", {0, 1}}])
    assert state.players["a"].health == 50.5
    assert State.step(state).players["a"].health == 51.5
  end

  test "attack charges the attacker and damages a same-square target" do
    state = connected() |> State.dispatch({:connect, "b", {0, 0}})
    attacked = State.dispatch(state, {:attack, "a", "b"})
    assert attacked.players["a"].health == 80
    assert attacked.players["b"].health == 0
    assert attacked.players["a"].player_kills == 1
    assert attacked.players["a"].charge_ready_tick == 10
    assert hd(State.dispatch(attacked, {:attack, "a", "b"}).recent).result == :not_ready
  end

  test "two charged hits banish the beast and earn the attacker a life" do
    state = State.new() |> State.dispatch({:connect, "a", {3, 3}})
    assert state.monster.health == 200

    hit = State.dispatch(state, {:attack, "a", :monster})
    assert hit.monster.health == 100
    assert hit.players["a"].monster_kills == 0
    assert hit.players["a"].health == 80
    assert hd(State.dispatch(hit, {:attack, "a", :monster}).recent).result == :not_ready

    banished = hit |> ticks(10) |> State.dispatch({:attack, "a", :monster})
    assert banished.monster.mode == :banished
    assert banished.monster.health == 0
    assert banished.players["a"].lives == 4
    assert banished.players["a"].monster_kills == 1
    assert ticks(banished, 59).monster.mode == :banished

    returned = ticks(banished, 60)
    assert returned.monster.health == 200
    assert returned.monster.position != {3, 3}

    assert hd(State.dispatch(returned, {:attack, "a", :monster}).recent).result ==
             :different_square
  end

  test "the reported 0,2 to preloaded 1,0 journey is accepted after 38 offline ticks" do
    state =
      connected()
      |> ticks(7)
      |> State.dispatch({:move, "a", {0, 1}})
      |> ticks(11)
      |> State.dispatch({:move, "a", {0, 2}})
      |> ticks(12)
      |> then(&put_in(&1.players["a"].explored, 7))
      |> State.dispatch({:disconnect, "a"})
      |> ticks(38)
      |> State.dispatch({:connect, "a", {1, 0}})

    assert state.players["a"].position == {1, 0}
    assert hd(state.recent).result == :ok
  end

  test "reconnection cannot explore a new square or exceed its movement budget" do
    player = %{
      Player.new("a", {0, 0}, 0)
      | explored: 32769,
        charge_ready_tick: 10,
        last_disconnect_tick: 0
    }

    assert {:error, :unexplored} = Player.reconnect(player, {0, 1}, 100)
    assert {:error, :too_far} = Player.reconnect(player, {3, 3}, 10)
    assert {:ok, %{position: {3, 3}}} = Player.reconnect(player, {3, 3}, 30)

    state =
      connected() |> State.dispatch({:disconnect, "a"}) |> State.dispatch({:connect, "a", {0, 2}})

    assert state.players["a"].position == {0, 0}
    assert hd(state.recent).result == :unexplored
  end

  test "online idle time does not accumulate offline movement credit" do
    player = %{Player.new("a", {0, 0}, 0) | explored: 65535, last_disconnect_tick: 1000}
    assert {:error, :too_far} = Player.reconnect(player, {0, 2}, 1000)
    assert {:error, :too_far} = Player.reconnect(player, {0, 2}, 1009)
    assert {:ok, %{position: {0, 2}}} = Player.reconnect(player, {0, 2}, 1010)
    assert {:error, :too_far} = Player.reconnect(player, {3, 3}, 1010)
    assert {:ok, %{position: {3, 3}}} = Player.reconnect(player, {3, 3}, 1020)
  end

  test "a reconnect cannot reuse a previous departure's movement credit" do
    state = connected() |> State.dispatch({:disconnect, "a"}) |> ticks(10)
    state = State.dispatch(state, {:connect, "a", {0, 0}})
    state = put_in(state.players["a"].explored, 65535)
    state = ticks(state, 100)
    state = State.dispatch(state, {:connect, "a", {0, 2}})
    assert hd(state.recent).result == :too_far
    assert state.players["a"].position == {0, 0}
  end

  test "offline sessions expire after 1200 ticks even across repeated deaths and respawns" do
    state = connected() |> State.dispatch({:disconnect, "a"}) |> ticks(1199)
    assert state.players["a"].last_offline_tick == 0
    state = State.dispatch(state, {:disconnect, "a"})
    expired = State.step(state)
    refute Map.has_key?(expired.players, "a")
    assert State.dispatch(expired, {:connect, "a", {0, 0}}).players["a"].health == 100
  end

  test "a remaining connected view prevents expiration and reconnect starts a new offline period" do
    state = connected() |> State.dispatch({:connect, "a", {0, 0}})
    state = state |> State.dispatch({:disconnect, "a"}) |> ticks(1200)
    assert state.players["a"].connected_views == 1
    state = state |> State.dispatch({:disconnect, "a"}) |> ticks(100)
    state = State.dispatch(state, {:connect, "a", {0, 0}})
    state = state |> ticks(10) |> State.dispatch({:disconnect, "a"})
    assert ticks(state, 1199).players["a"]
    refute Map.has_key?(ticks(state, 1200).players, "a")
  end

  test "the monster walks server-side once every three seconds and is reproducible from a seed" do
    state = State.new({7, 8, 9})
    assert ticks(state, 29).monster.position == state.monster.position
    moved = ticks(state, 30)
    assert Player.distance(state.monster.position, moved.monster.position) == 1
    assert moved.monster.last_move_tick == 30
    assert ticks(state, 100) == ticks(State.new({7, 8, 9}), 100)

    Enum.reduce(1..100, state, fn _, current ->
      next = ticks(current, 30)
      assert Player.valid_position?(next.monster.position)
      assert Player.distance(current.monster.position, next.monster.position) == 1
      next
    end)
  end

  test "disconnected players neither attract explosions nor take splash damage" do
    state =
      State.new()
      |> State.dispatch({:connect, "offline", {3, 3}})
      |> State.dispatch({:disconnect, "offline"})

    state = %{state | tick: 29}
    moved = State.step(state)
    assert moved.monster.mode == :idle
    refute moved.monster.position == {3, 3}
    occupied = State.dispatch(state, {:connect, "online", {3, 3}})
    exploded = State.step(occupied)
    assert exploded.monster.mode == :exploding
    assert exploded.players["online"].health == 51
    assert exploded.players["offline"].health == 90
  end
end
