defmodule FogOfWarFrontierWeb.MultiLive do
  use FogOfWarFrontierWeb, :live_view
  alias FogOfWarFrontier.Game
  alias FogOfWarFrontier.Game.Map, as: GameMap

  @gc_interval_ticks 200

  def mount(_, session, socket) do
    connection = if connected?(socket), do: get_connect_info(socket, :session), else: nil
    server = Map.get(session, "game_server", Game)

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(FogOfWarFrontier.PubSub, Game.topic(server))

    if connected?(socket), do: Process.send_after(self(), :report_memory, 1000)

    socket =
      assign(socket,
        lat: 0,
        lon: 0,
        places: [],
        neighbors: [],
        multiplayer: true,
        route_prefix: "/multi",
        player_id:
          if(connected?(socket),
            do: connection && connection["frontier_player_id"],
            else: session["frontier_player_id"]
          ),
        game_server: server,
        entities_by_id: %{},
        player_state: nil,
        player_status: nil,
        acknowledged_life: 0,
        fresh_join: false,
        respawn_pending: nil
      )

    {:ok, socket |> stream(:tiles, []) |> stream(:objects, []) |> stream(:entities, [])}
  end

  def handle_params(%{"lat" => lat, "lon" => lon}, _, socket) do
    with {lat, ""} <- Integer.parse(lat),
         {lon, ""} <- Integer.parse(lon),
         true <- lat in 0..3 and lon in 0..3 do
      fresh_join =
        connected?(socket) && socket.assigns.player_id &&
          is_nil(read_player(socket.assigns.game_server, socket.assigns.player_id))

      socket =
        if fresh_join, do: assign(socket, acknowledged_life: -1, fresh_join: true), else: socket

      game =
        if connected?(socket) && socket.assigns.player_id do
          Game.observe_sync(
            socket.assigns.game_server,
            socket.assigns.player_id,
            self(),
            {lat, lon}
          )
        else
          read(socket.assigns.game_server)
        end

      socket =
        if connected?(socket) && !Map.has_key?(socket.private, :frontier_gc),
          do: put_private(socket, :frontier_gc, {game.tick, 0}),
          else: socket

      player = game.players[socket.assigns.player_id]

      {view_lat, view_lon} =
        if connected?(socket) && player && player.life <= socket.assigns.acknowledged_life,
          do: player.position,
          else: {lat, lon}

      tiles = for y <- 0..3, x <- 0..3, do: %{id: "#{y}-#{x}", lat: y, lon: x}

      socket =
        socket
        |> assign(
          lat: view_lat,
          lon: view_lon,
          path: path(view_lat, view_lon),
          neighbors: FogOfWarFrontierWeb.MapLive.neighbors(view_lat, view_lon)
        )
        |> stream(:tiles, tiles, reset: true)
        |> stream(:objects, tiles, reset: true)
        |> refresh_game(game)

      socket =
        if {lat, lon} != {view_lat, view_lon},
          do: push_patch(socket, to: path(view_lat, view_lon)),
          else: socket

      {:noreply, socket}
    else
      _ -> {:noreply, push_navigate(socket, to: path(0, 0))}
    end
  end

  def handle_params(_, _, socket), do: {:noreply, push_navigate(socket, to: path(0, 0))}

  def handle_info(:report_memory, socket) do
    alias FogOfWarFrontier.Game.LiveMemory

    Phoenix.PubSub.broadcast(
      FogOfWarFrontier.PubSub,
      LiveMemory.topic(socket.assigns.game_server),
      {:live_memory, LiveMemory.sample(socket.assigns.player_id, socket.transport_pid)}
    )

    Process.send_after(self(), :report_memory, 1000)
    {:noreply, socket}
  end

  def handle_info({:game_tick, server, tick}, %{assigns: %{game_server: server}} = socket) do
    socket = socket |> schedule_gc(tick) |> refresh_view()
    player = socket.assigns.player_state

    socket =
      if player && is_nil(socket.assigns.respawn_pending) &&
           player.position != {socket.assigns.lat, socket.assigns.lon} do
        {lat, lon} = player.position
        push_patch(socket, to: path(lat, lon))
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:garbage_collect, :frontier_gc, _result}, socket), do: {:noreply, socket}

  def handle_info({:monster_attack, server, attack}, %{assigns: %{game_server: server}} = socket) do
    if attack.position == {socket.assigns.lat, socket.assigns.lon} do
      sprite_id =
        if attack.player == socket.assigns.player_id,
          do: "player",
          else: "entities-player-#{attack.player}"

      {:noreply,
       push_event(socket, "frontier:elixir_strike", %{
         sprite_id: sprite_id,
         defeated: attack.defeated,
         slayer: attack.defeated && attack.player == socket.assigns.player_id
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event("attack_monster", _, socket) do
    if socket.assigns.player_id && is_nil(socket.assigns.respawn_pending) do
      game = Game.act(socket.assigns.game_server, {:attack, socket.assigns.player_id, :monster})
      {:noreply, refresh_game(socket, game)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("sync_player", _, socket) do
    {:noreply, socket |> assign(player_status: nil) |> refresh_view()}
  end

  def handle_event("respawn_ready", %{"life" => life} = params, socket) do
    game = read(socket.assigns.game_server)
    player = game.players[socket.assigns.player_id]

    if player && life == player.life && life == socket.assigns.respawn_pending do
      {lat, lon} = player.position

      socket =
        socket
        |> assign(
          acknowledged_life: life,
          fresh_join: false,
          respawn_pending: nil,
          player_status: nil
        )
        |> refresh_game(game)
        |> push_patch(to: path(lat, lon))

      socket =
        if Map.get(params, "notify", true),
          do: push_event(socket, "frontier:respawned", %{life: life}),
          else: socket

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def render(assigns), do: FogOfWarFrontierWeb.MapScene.scene(assigns)

  defp path(lat, lon), do: "/multi/lat/#{lat}/lon/#{lon}"
  defp read(Game), do: GameMap.snapshot()
  defp read(server), do: Game.snapshot(server)

  defp schedule_gc(socket, tick) do
    {previous, elapsed} = Map.get(socket.private, :frontier_gc, {tick, 0})

    # Actions can publish the same tick again, and a game reset restarts the clock.
    elapsed = elapsed + if(tick >= previous, do: tick - previous, else: tick)

    if elapsed >= @gc_interval_ticks do
      :erlang.garbage_collect(self(), async: :frontier_gc)
      :erlang.garbage_collect(socket.transport_pid, async: :frontier_gc)
    end

    put_private(socket, :frontier_gc, {tick, rem(elapsed, @gc_interval_ticks)})
  end

  defp read_player(Game, id), do: GameMap.player(id)
  defp read_player(server, id), do: read(server).players[id]

  defp refresh_view(%{assigns: %{game_server: Game} = assigns} = socket) do
    view = GameMap.view(assigns.player_id, {assigns.lat, assigns.lon})
    refresh_projection(socket, view)
  end

  defp refresh_view(socket), do: refresh_game(socket, read(socket.assigns.game_server))

  defp refresh_game(%{assigns: assigns} = socket, game) do
    refresh_projection(socket, %{
      player: game.players[assigns.player_id],
      tick: game.tick,
      paused: Map.get(game, :paused, false),
      entities: GameMap.entities(game, {assigns.lat, assigns.lon}, assigns.player_id)
    })
  end

  defp refresh_projection(socket, %{player: player} = view) do
    socket =
      if connected?(socket) && player && player.life > socket.assigns.acknowledged_life &&
           socket.assigns.respawn_pending != player.life do
        socket
        |> assign(respawn_pending: player.life)
        |> push_event("frontier:respawn", %{
          life: player.life,
          player_id: player.id,
          fresh_join: socket.assigns.fresh_join
        })
      else
        socket
      end

    socket =
      if socket.assigns.respawn_pending, do: socket, else: assign(socket, player_state: player)

    socket =
      if player && connected?(socket) do
        status = %{
          paused: view.paused,
          health: player.health,
          last_attack_tick: player.last_attack_tick,
          clearing_cache: not is_nil(socket.assigns.respawn_pending),
          dead: player.health <= 0,
          life: player.life,
          lives: player.lives,
          respawn_remaining_ms:
            if(player.death_tick,
              do:
                max(0, player.death_tick + Game.Rules.respawn_ticks() - view.tick) *
                  Game.Rules.tick_ms(),
              else: 0
            ),
          move_remaining_ms: max(0, player.charge_ready_tick - view.tick) * Game.Rules.tick_ms()
        }

        if status != socket.assigns.player_status do
          socket |> assign(player_status: status) |> push_event("frontier:player", status)
        else
          socket
        end
      else
        socket
      end

    if socket.assigns.respawn_pending do
      socket
    else
      entities = view.entities

      previous = socket.assigns.entities_by_id
      current = Map.new(entities, &{&1.id, &1})

      socket =
        Enum.reduce(previous, socket, fn {id, entity}, acc ->
          if Map.has_key?(current, id), do: acc, else: stream_delete(acc, :entities, entity)
        end)

      socket =
        entities
        |> Enum.with_index()
        |> Enum.reduce(socket, fn {entity, index}, acc ->
          if previous[entity.id] == entity,
            do: acc,
            else: stream_insert(acc, :entities, entity, at: index)
        end)

      assign(socket, entities_by_id: current)
    end
  end
end
