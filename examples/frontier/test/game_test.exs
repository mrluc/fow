defmodule FogOfWarFrontier.GameTest do
  use ExUnit.Case, async: false
  alias FogOfWarFrontier.Game
  alias FogOfWarFrontier.Game.Map, as: GameMap

  test "enforces echoed movement in ETS without redirecting the sending view" do
    id = "echo-#{System.unique_integer([:positive])}"
    Game.observe(id, self(), {0, 0})
    :sys.get_state(Game)
    assert %{health: 100, connected_views: 1, position: {0, 0}, explored: 51} = GameMap.player(id)
    Game.observe(id, self(), {3, 3})
    :sys.get_state(Game)
    player = GameMap.player(id)
    assert player.position == {0, 0}
    assert player.explored == 51
    assert player.health == 100
    assert player.connected_views == 1
    assert Enum.any?(GameMap.occupants({0, 0}), &(&1.id == id))
  end

  test "reconnecting across explored squares uses elapsed movement budget even while another view remains" do
    server = :frontier_rejoin_existing_view_test
    start_supervised!({Game, name: server, automatic: false})

    old_view =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> Process.exit(old_view, :kill) end)
    Game.observe_sync(server, "walker", old_view, {0, 0})

    offline_view =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    Game.observe_sync(server, "walker", offline_view, {0, 0})
    Game.act(server, {:move, "walker", {0, 1}})
    for _ <- 1..10, do: Game.step(server)
    Game.act(server, {:move, "walker", {0, 2}})
    for _ <- 1..10, do: Game.step(server)
    Game.act(server, {:move, "walker", {0, 1}})
    for _ <- 1..10, do: Game.step(server)
    Game.act(server, {:move, "walker", {0, 0}})
    Process.exit(offline_view, :kill)
    wait_for_views(server, 1, 100)
    for _ <- 1..30, do: Game.step(server)
    game = Game.observe_sync(server, "walker", self(), {0, 2})
    assert game.players["walker"].position == {0, 2}
    assert game.players["walker"].connected_views == 2
  end

  test "disconnected static renders do not register players" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Phoenix.ConnTest.dispatch(conn, FogOfWarFrontierWeb.Endpoint, :get, "/lat/0/lon/0")
    id = Plug.Conn.get_session(conn, :frontier_player_id)
    assert is_binary(id)
    assert GameMap.player(id) == nil
  end

  test "the ETS view follows square changes while retaining the local player's position" do
    server = :frontier_square_projection_test
    start_supervised!({Game, name: server, automatic: false})
    table = :sys.get_state(server).table
    Game.act(server, {:connect, "viewer", {0, 0}})
    Game.act(server, {:connect, "neighbor", {0, 0}})
    Game.act(server, {:connect, "elsewhere", {3, 3}})

    assert %{tick: 0, paused: false, entities: [%{id: "player-neighbor"}]} =
             GameMap.view("viewer", {0, 0}, table)

    Game.act(server, {:move, "neighbor", {0, 1}})
    assert %{tick: 0, entities: []} = GameMap.view("viewer", {0, 0}, table)

    assert %{player: %{position: {0, 0}}, entities: [%{id: "player-neighbor"}]} =
             GameMap.view("viewer", {0, 1}, table)

    Game.pause(server)
    assert %{tick: 0, paused: true} = GameMap.view("viewer", {0, 1}, table)

    assert %{entities: [%{kind: :monster}, %{id: "player-elsewhere"}]} =
             GameMap.view("viewer", {3, 3}, table)
  end

  test "expiration removes the player's ETS record as well as the snapshot" do
    server = :frontier_expiry_test
    start_supervised!({Game, name: server, automatic: false})
    Game.act(server, {:connect, "expired", {0, 0}})
    Game.act(server, {:disconnect, "expired"})
    table = :sys.get_state(server).table
    assert :ets.lookup(table, {:player, "expired"}) != []
    for _ <- 1..1200, do: Game.step(server)
    assert :ets.lookup(table, {:player, "expired"}) == []
    refute Map.has_key?(Game.snapshot(server).players, "expired")
    assert %{player: nil, entities: []} = GameMap.view("expired", {0, 0}, table)
  end

  test "an automatic game keeps ticking across actions and reads" do
    server = :frontier_clock_test
    Phoenix.PubSub.subscribe(FogOfWarFrontier.PubSub, Game.topic(server))
    start_supervised!({Game, name: server})
    assert_receive {:game_tick, ^server, 0}
    assert_receive {:game_tick, ^server, 1}, 1000
    Game.act(server, {:connect, "clock-player", {0, 0}})
    assert Game.snapshot(server).players["clock-player"]
    assert_receive {:game_tick, ^server, 2}, 1000
    assert_receive {:game_tick, ^server, 3}, 1000
    assert Game.snapshot(server).tick >= 3
  end

  defp wait_for_views(_, _, 0), do: flunk("View disconnect was not processed")

  defp wait_for_views(server, count, tries) do
    if Game.snapshot(server).players["walker"].connected_views != count do
      Process.sleep(5)
      wait_for_views(server, count, tries - 1)
    end
  end
end
