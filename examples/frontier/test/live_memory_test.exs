defmodule FogOfWarFrontier.LiveMemoryTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias FogOfWarFrontier.Game
  alias Game.LiveMemory
  @endpoint FogOfWarFrontierWeb.Endpoint

  test "samples report actual process bytes and expire at three seconds" do
    transport = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(transport, :kill) end)
    sample = LiveMemory.sample("alice", transport)
    assert sample.bytes > 0
    assert is_integer(sample.messages)
    assert sample.tab_id =~ inspect(transport)
    assert {:memory, sample.socket_bytes} == Process.info(transport, :memory)

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

    assert_receive {:live_memory,
                    %{player_id: "memory-player", bytes: bytes, socket_bytes: socket_bytes}},
                   2500

    assert bytes > 0
    assert socket_bytes > 0

    {:ok, inspector, _} =
      live_isolated(build_conn(), FogOfWarFrontierWeb.GameInspectorLive,
        session: %{"game_server" => server}
      )

    refute has_element?(inspector, "#live-memory-capacity")

    for {id, bytes} <- [{"tab-a", 1024}, {"tab-b", 3072}],
        do:
          send(
            inspector.pid,
            {:live_memory,
             %{player_id: "alice", tab_id: id, bytes: bytes, socket_bytes: 1024, messages: 0}}
          )

    assert render(inspector) =~ "2 connected tabs"
    assert has_element?(inspector, "#live-memory-total", "6.0 KiB")
    assert has_element?(inspector, "#live-memory-capacity", "256 MiB: 87381")
    assert has_element?(inspector, "tr[data-memory-tab=tab-a] td:nth-child(4)", "1.0 KiB")
    assert has_element?(inspector, "tr[data-memory-tab=tab-a] td:nth-child(5)", "2.0 KiB")
    assert has_element?(inspector, "tr[data-memory-tab=tab-b]")
  end
end
