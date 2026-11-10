defmodule FogOfWarFrontier.MultiLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias FogOfWarFrontier.Game
  @endpoint FogOfWarFrontierWeb.Endpoint

  defp player_conn(id, server) do
    session = %{"frontier_player_id" => id, "game_server" => server}

    build_conn()
    |> Plug.Test.init_test_session(session)
    |> Plug.Conn.put_private(:live_view_connect_info, %{session: session})
  end

  test "collects the LiveView and transport 200 ticks after joining" do
    server = :frontier_gc_test
    start_supervised!({Game, name: server, automatic: false})
    for _ <- 1..37, do: Game.step(server)

    {:ok, view, _} = live(player_conn("scout", server), "/multi/lat/0/lon/0")
    live_pid = view.pid
    transport = :sys.get_state(live_pid).socket.transport_pid
    for _ <- 1..199, do: Game.step(server)
    Game.pause(server)
    Game.resume(server)

    assert :sys.get_state(live_pid).socket.private.frontier_gc == {236, 199}
    :erlang.trace(live_pid, true, [:garbage_collection])
    :erlang.trace(transport, true, [:garbage_collection])
    Game.step(server)

    assert_receive {:trace, ^live_pid, :gc_major_end, _}, 1000
    assert_receive {:trace, ^transport, :gc_major_end, _}, 1000
    assert :sys.get_state(live_pid).socket.private.frontier_gc == {237, 0}
  end

  test "two streamed views see only other entities on the square being viewed" do
    server = :frontier_multi_test
    start_supervised!({Game, name: server, automatic: false})
    Game.act(server, {:connect, "alice", {0, 0}})
    Game.act(server, {:connect, "bob", {0, 0}})
    Game.act(server, {:connect, "far-away", {3, 2}})
    {:ok, alice, _} = live(player_conn("alice", server), "/multi/lat/0/lon/0")
    {:ok, bob, _} = live(player_conn("bob", server), "/multi/lat/0/lon/0")
    assert has_element?(alice, "#terrain-tiles[phx-update=stream] .terrain-tile")
    assert has_element?(alice, "#terrain-objects[phx-update=stream] .tree")
    assert has_element?(alice, "#multi-entities[phx-update=stream] #entities-player-bob")
    refute has_element?(alice, "#entities-player-alice")
    refute has_element?(alice, "#entities-player-far-away")
    refute has_element?(alice, ".entity-monster")
    assert has_element?(bob, "#entities-player-alice")
    Game.step(server, [{:move, "bob", {0, 1}}])
    refute has_element?(alice, "#entities-player-bob")
    assert_patch(bob, "/multi/lat/0/lon/1")
    assert has_element?(bob, "#player.at-0-1")
  end

  test "health and movement agree with the inspector, including healing and rejected moves" do
    server = :frontier_multi_authority_test
    start_supervised!({Game, name: server, automatic: false})
    Game.act(server, {:connect, "alice", {3, 3}})
    Game.act(server, {:disconnect, "alice"})
    {:ok, view, _} = live(player_conn("alice", server), "/multi/lat/3/lon/3")

    {:ok, inspector, _} =
      live_isolated(build_conn(), FogOfWarFrontierWeb.GameInspectorLive,
        session: %{"game_server" => server}
      )

    for _ <- 1..30, do: Game.step(server)
    assert has_element?(view, "#player[data-health='51']")
    assert_push_event(view, "frontier:player", %{health: 51})
    Game.step(server)
    assert has_element?(view, "#player[data-health='52.0']")
    inspector |> element("button[phx-click=player][phx-value-id=alice]") |> render_click()
    assert has_element?(inspector, "pre[data-player-detail=alice]", "health: 52.0")
    view |> element("a[href='/multi/lat/2/lon/2']") |> render_click()
    assert has_element?(view, "#player.at-2-2")
    assert has_element?(inspector, "pre[data-player-detail=alice]", "position: {2, 2}")
    view |> element("a[href='/multi/lat/1/lon/1']") |> render_click()
    assert_patch(view, "/multi/lat/2/lon/2")
    assert has_element?(view, "#player.at-2-2")
    assert Game.snapshot(server).players["alice"].connected_views == 1
  end

  test "death counts one life and respawn waits for the cache-clear acknowledgement" do
    server = :frontier_respawn_test
    start_supervised!({Game, name: server, automatic: false})
    {:ok, view, _} = live(player_conn("alice", server), "/multi/lat/0/lon/0")
    Game.act(server, {:connect, "bob", {0, 0}})
    Game.act(server, {:attack, "bob", "alice"})

    assert_push_event(view, "frontier:player", %{
      health: 0,
      dead: true,
      lives: 2,
      respawn_remaining_ms: 5000
    })

    for _ <- 1..49, do: Game.step(server)
    assert Game.snapshot(server).players["alice"].health == 0
    Game.step(server)
    assert_push_event(view, "frontier:respawn", %{life: 1, player_id: "alice"})
    assert has_element?(view, "#player.at-0-0")
    refute_receive {_, {:patch, _, _}}, 10
    render_hook(view, "respawn_ready", %{"life" => 0})
    refute_receive {_, {:patch, _, _}}, 10
    player = Game.snapshot(server).players["alice"]
    {lat, lon} = player.position
    render_hook(view, "respawn_ready", %{"life" => 1})
    assert_patch(view, "/multi/lat/#{lat}/lon/#{lon}")
    assert_push_event(view, "frontier:player", %{health: 100, dead: false, lives: 2, life: 1})
    assert_push_event(view, "frontier:respawned", %{life: 1})
    assert player.explored == 0
    # Clearing the old fog must not leave the newly presented spawn unexplored.
    assert FogOfWarFrontier.Game.Player.explored?(
             Game.snapshot(server).players["alice"],
             player.position
           )
  end

  test "monster explosion damage reaches the player HUD from the game" do
    server = :frontier_monster_damage_test
    start_supervised!({Game, name: server, automatic: false})
    Game.act(server, {:connect, "scout", {3, 3}})
    {:ok, view, _} = live(player_conn("scout", server), "/multi/lat/3/lon/3")
    for _ <- 1..30, do: Game.step(server)
    health = Game.snapshot(server).players["scout"].health
    assert health < 100
    assert has_element?(view, "#player[data-health='#{health}']")
    assert_push_event(view, "frontier:player", %{health: ^health})
  end

  test "clicking the beast casts a strike visible to both players on the square" do
    server = :frontier_multi_strike_test
    start_supervised!({Game, name: server, automatic: false})
    Game.act(server, {:connect, "scout", {3, 3}})
    Game.act(server, {:connect, "witness", {3, 3}})
    {:ok, scout, _} = live(player_conn("scout", server), "/multi/lat/3/lon/3")
    {:ok, witness, _} = live(player_conn("witness", server), "/multi/lat/3/lon/3")
    scout |> element("button.entity-monster") |> render_click()
    assert Game.snapshot(server).monster.health == 100
    assert_push_event(scout, "frontier:elixir_strike", %{sprite_id: "player"})
    assert_push_event(witness, "frontier:elixir_strike", %{sprite_id: "entities-player-scout"})
  end

  test "monster is rendered only on the current square, with stable stream IDs" do
    server = :frontier_multi_monster_test
    start_supervised!({Game, name: server, automatic: false})
    Game.act(server, {:connect, "scout", {3, 3}})
    {:ok, view, _} = live(player_conn("scout", server), "/multi/lat/3/lon/3")
    assert has_element?(view, "#entities-monster-split-brain .entity-monster")
    assert has_element?(view, "a[href='/multi/lat/2/lon/2']")
    for _ <- 1..30, do: Game.step(server)
    assert has_element?(view, ".entity-monster.monster-exploding")
    assert has_element?(view, "#player.at-3-3")
  end
end
