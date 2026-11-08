defmodule FogOfWarFrontier.GameRestartTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias FogOfWarFrontier.Game
  alias FogOfWarFrontier.Game.{Cache, State}
  @endpoint FogOfWarFrontierWeb.Endpoint

  defp restart(server) do
    old = Process.whereis(server)
    ref = Process.monitor(old)
    Process.exit(old, :kill)
    assert_receive {:DOWN, ^ref, :process, ^old, :killed}
    await_restart(server, old, 100)
  end

  defp await_restart(_, _, 0), do: flunk("Game did not restart")

  defp await_restart(server, old, attempts) do
    case Process.whereis(server) do
      pid when is_pid(pid) and pid != old ->
        Game.snapshot(server)

      _ ->
        Process.sleep(10)
        await_restart(server, old, attempts - 1)
    end
  end

  test "killing Game preserves checkpoint and restores monitoring of connected views" do
    cache = :frontier_restart_cache
    server = :frontier_restart_game
    keeper = start_supervised!({Cache, name: cache, table: :anonymous})
    start_supervised!({Game, name: server, cache: cache, automatic: false, seed: {7, 8, 9}})

    view =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> if Process.alive?(view), do: Process.exit(view, :kill) end)
    Game.observe_sync(server, "alice", view, {0, 0})
    Game.step(server, [{:move, "alice", {0, 1}}])
    Game.pause(server)
    before = Game.snapshot(server)
    table = :sys.get_state(server).table
    assert :ets.info(table, :owner) == keeper
    assert restart(server) == before
    assert :sys.get_state(server).table == table
    assert Map.values(:sys.get_state(server).views) == [{"alice", view}]
    assert Game.step(server) == State.step(before)
    Process.exit(view, :kill)
    # Force delivery of the restored monitor before inspecting the connection count.
    ref = Process.monitor(view)
    assert_receive {:DOWN, ^ref, :process, ^view, _}
    eventually_disconnected(server, 100)
  end

  defp eventually_disconnected(_, 0), do: flunk("Restored monitor did not disconnect the player")

  defp eventually_disconnected(server, attempts) do
    if Game.snapshot(server).players["alice"].connected_views != 0 do
      Process.sleep(10)
      eventually_disconnected(server, attempts - 1)
    end
  end

  test "a connected player view and inspector keep working after Game is killed" do
    cache = :frontier_lv_restart_cache
    server = :frontier_lv_restart_game
    start_supervised!({Cache, name: cache, table: :anonymous})
    start_supervised!({Game, name: server, cache: cache, automatic: false})
    session = %{"frontier_player_id" => "alice", "game_server" => server}

    conn =
      build_conn()
      |> Plug.Test.init_test_session(session)
      |> Plug.Conn.put_private(:live_view_connect_info, %{session: session})

    {:ok, player, _} = live(conn, "/multi/lat/0/lon/0")

    {:ok, inspector, _} =
      live_isolated(build_conn(), FogOfWarFrontierWeb.GameInspectorLive,
        session: %{"game_server" => server}
      )

    before = Game.snapshot(server)
    assert restart(server) == before
    player |> element("a[href='/multi/lat/0/lon/1']") |> render_click()
    assert has_element?(player, "#player.at-0-1")
    inspector |> element("#debug-players button[phx-value-id=alice]") |> render_click()
    assert has_element?(inspector, "pre[data-player-detail=alice]", "position: {0, 1}")
    assert Game.snapshot(server).players["alice"].connected_views == 1
  end

  test "inspector reset respawns the live player and checkpoints the new match" do
    cache = :frontier_reset_cache
    server = :frontier_reset_game
    start_supervised!({Cache, name: cache, table: :anonymous})
    start_supervised!({Game, name: server, cache: cache, automatic: false})
    session = %{"frontier_player_id" => "alice", "game_server" => server}

    conn =
      build_conn()
      |> Plug.Test.init_test_session(session)
      |> Plug.Conn.put_private(:live_view_connect_info, %{session: session})

    {:ok, player, _} = live(conn, "/multi/lat/0/lon/0")

    {:ok, inspector, _} =
      live_isolated(build_conn(), FogOfWarFrontierWeb.GameInspectorLive,
        session: %{"game_server" => server}
      )

    inspector |> element("button[phx-click=reset_game]") |> render_click()
    assert_push_event(player, "frontier:respawn", %{life: 1, player_id: "alice"})
    fresh = Game.snapshot(server).players["alice"]
    assert fresh.health == 100
    assert fresh.lives == 3
    assert fresh.explored == 0
    assert fresh.connected_views == 1
    render_hook(player, "respawn_ready", %{"life" => 1})
    {lat, lon} = fresh.position
    assert_patch(player, "/multi/lat/#{lat}/lon/#{lon}")
    before = Game.snapshot(server)
    assert restart(server) == before
    assert has_element?(player, "#player.at-#{lat}-#{lon}")
  end
end
