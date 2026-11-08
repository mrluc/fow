defmodule FogOfWarFrontier.GameInspectorTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias FogOfWarFrontier.Game
  @endpoint FogOfWarFrontierWeb.Endpoint

  test "two LiveViews observe a manually stepped game without timers" do
    server = :frontier_step_test
    start_supervised!({Game, name: server, automatic: false})
    Game.act(server, {:connect, "alice", {0, 0}})
    Game.act(server, {:connect, "bob", {0, 0}})

    {:ok, first, _} =
      live_isolated(build_conn(), FogOfWarFrontierWeb.GameInspectorLive,
        session: %{"game_server" => server}
      )

    {:ok, second, _} =
      live_isolated(build_conn(), FogOfWarFrontierWeb.GameInspectorLive,
        session: %{"game_server" => server}
      )

    assert has_element?(first, "#game-tick", "0")
    assert has_element?(first, ".debug-player-count", "2")
    assert has_element?(first, ".debug-monster")

    Game.step(server, [{:move, "alice", {0, 1}}])

    for view <- [first, second] do
      assert has_element?(view, "#game-tick", "1")
      view |> element("button[phx-click=player][phx-value-id=alice]") |> render_click()
      assert has_element?(view, "pre[data-player-detail=alice]", "position: {0, 1}")
    end

    before = Game.snapshot(server)

    first
    |> element("button[phx-click=square][phx-value-lat='3'][phx-value-lon='3']")
    |> render_click()

    assert Game.snapshot(server) == before
    assert render(first) =~ "Square {3, 3}"
    assert has_element?(first, "img[src='/images/monster/256/monster-idle.png'][width='256']")
  end

  test "development route inspects the default game" do
    {:ok, view, _} = live(build_conn(), "/dev/game")
    assert render(view) =~ "FogOfWarFrontier.Game"
    assert length(view |> render() |> Floki.parse_document!() |> Floki.find(".debug-tile")) == 16
  end

  test "pause freezes automatic ticks and moves; inspector can step once and resume" do
    server = :frontier_pause_test
    start_supervised!({Game, name: server, automatic: false})
    Game.act(server, {:connect, "alice", {0, 0}})

    {:ok, view, _} =
      live_isolated(build_conn(), FogOfWarFrontierWeb.GameInspectorLive,
        session: %{"game_server" => server}
      )

    view |> element("#pause-game") |> render_click()
    before = Game.snapshot(server)
    assert before.paused
    send(Process.whereis(server), :tick)
    assert Game.snapshot(server) == before
    after_move = Game.act(server, {:move, "alice", {0, 1}})
    assert after_move.players == before.players
    assert after_move.monster == before.monster
    assert has_element?(view, "#pause-game", "Resume game")
    assert has_element?(view, ".debug-entities .entity-player")
    assert has_element?(view, ".debug-entities .entity-monster")
    view |> element("button[phx-click=entity][phx-value-id=alice]") |> render_click()
    assert has_element?(view, "pre.selected[data-player-detail=alice]")
    view |> element("#step-game") |> render_click()
    assert Game.snapshot(server).tick == before.tick + 1
    assert Game.snapshot(server).paused
    view |> element("#pause-game") |> render_click()
    send(Process.whereis(server), :tick)
    assert Game.snapshot(server).tick == before.tick + 2
    refute Game.snapshot(server).paused
  end
end
