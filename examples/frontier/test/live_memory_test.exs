defmodule FogOfWarFrontier.LiveMemoryTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias FogOfWarFrontier.Game
  alias Game.LiveMemory
  @endpoint FogOfWarFrontierWeb.Endpoint

  test "samples report actual process bytes and expire at three seconds" do
    sample = LiveMemory.sample("alice")
    assert sample.bytes > 0
    assert is_integer(sample.messages)
    assert sample.view_id =~ inspect(self())

    samples = %{
      "old" => Map.put(sample, :received_at, 1000),
      "new" => Map.put(sample, :received_at, 1001)
    }

    assert Map.keys(LiveMemory.prune(samples, 4000)) == ["new"]
  end

  test "connected player publishes and inspector sums separate views" do
    server = :memory_test_game
    start_supervised!({Game, name: server, automatic: false})
    Phoenix.PubSub.subscribe(FogOfWarFrontier.PubSub, LiveMemory.topic(server))
    session = %{"frontier_player_id" => "memory-player", "game_server" => server}

    conn =
      build_conn()
      |> Plug.Test.init_test_session(session)
      |> Plug.Conn.put_private(:live_view_connect_info, %{session: session})

    {:ok, _player, _} = live(conn, "/multi/lat/0/lon/0")
    assert_receive {:live_memory, %{player_id: "memory-player", bytes: bytes}}, 2500
    assert bytes > 0

    {:ok, inspector, _} =
      live_isolated(build_conn(), FogOfWarFrontierWeb.GameInspectorLive,
        session: %{"game_server" => server}
      )

    for id <- ["tab-a", "tab-b"],
        do:
          send(
            inspector.pid,
            {:live_memory, %{player_id: "alice", view_id: id, bytes: 1024, messages: 0}}
          )

    assert render(inspector) =~ "2 connected views"
    assert has_element?(inspector, "#live-memory-total", "2.0 KiB")
    assert has_element?(inspector, "tr[data-memory-view=tab-a]")
    assert has_element?(inspector, "tr[data-memory-view=tab-b]")
  end
end
