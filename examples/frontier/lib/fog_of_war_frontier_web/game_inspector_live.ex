defmodule FogOfWarFrontierWeb.GameInspectorLive do
  use FogOfWarFrontierWeb, :live_view
  alias FogOfWarFrontier.Game
  alias FogOfWarFrontier.Game.Map, as: GameMap

  def mount(_, session, socket) do
    # The named override comes from a trusted LiveView test session, never URL params.
    server = Map.get(session, "game_server", Game)

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(FogOfWarFrontier.PubSub, Game.topic(server))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(FogOfWarFrontier.PubSub, Game.LiveMemory.topic(server))
      Process.send_after(self(), :prune_memory, 1000)
    end

    {:ok,
     assign(socket,
       memory_samples: %{},
       last_memory_bytes: nil,
       game_server: server,
       game: read(server),
       square: {0, 0},
       selected: nil
     )}
  end

  def handle_info({:live_memory, sample}, socket) do
    now = System.monotonic_time(:millisecond)

    samples =
      socket.assigns.memory_samples
      |> Game.LiveMemory.prune(now)
      |> Map.put(sample.tab_id, Map.put(sample, :received_at, now))

    {:noreply,
     assign(socket,
       memory_samples: samples,
       last_memory_bytes: Game.LiveMemory.total_bytes(sample)
     )}
  end

  def handle_info(:prune_memory, socket) do
    Process.send_after(self(), :prune_memory, 1000)

    {:noreply,
     assign(socket,
       memory_samples:
         Game.LiveMemory.prune(socket.assigns.memory_samples, System.monotonic_time(:millisecond))
     )}
  end

  def handle_info({:game_tick, server, _}, %{assigns: %{game_server: server}} = socket) do
    game = read(server)

    square =
      case if(socket.assigns.selected == :monster,
             do: game.monster,
             else: game.players[socket.assigns.selected]
           ) do
        nil -> socket.assigns.square
        player -> player.position
      end

    {:noreply, assign(socket, game: game, square: square)}
  end

  def handle_event("pause_game", _, socket) do
    game =
      if Map.get(socket.assigns.game, :paused, false),
        do: Game.resume(socket.assigns.game_server),
        else: Game.pause(socket.assigns.game_server)

    {:noreply, assign(socket, game: game)}
  end

  def handle_event("step_game", _, socket) do
    if Map.get(socket.assigns.game, :paused, false) do
      {:noreply, assign(socket, game: Game.step(socket.assigns.game_server))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("entity", params, socket), do: handle_event("player", params, socket)

  def handle_event("monster", _, socket),
    do:
      {:noreply, assign(socket, selected: :monster, square: socket.assigns.game.monster.position)}

  def handle_event("reset_game", _, socket) do
    game = Game.reset(socket.assigns.game_server)
    {:noreply, assign(socket, game: game, selected: nil, square: {0, 0})}
  end

  def handle_event("square", %{"lat" => lat, "lon" => lon}, socket) do
    with {lat, ""} <- Integer.parse(lat),
         {lon, ""} <- Integer.parse(lon),
         true <- lat in 0..3 and lon in 0..3 do
      {:noreply, assign(socket, square: {lat, lon}, selected: nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("player", %{"id" => id}, socket) do
    case socket.assigns.game.players[id] do
      nil -> {:noreply, socket}
      player -> {:noreply, assign(socket, selected: id, square: player.position)}
    end
  end

  defp memory_size(bytes), do: "#{Float.round(bytes / 1024, 1)} KiB"

  defp read(Game), do: GameMap.snapshot()
  defp read(server), do: Game.snapshot(server)

  defp occupants(game, square),
    do:
      game.players
      |> Map.values()
      |> Enum.filter(&(&1.position == square))
      |> Enum.sort_by(& &1.id)

  def render(assigns) do
    count = map_size(assigns.memory_samples)

    bytes =
      Enum.sum(for {_, sample} <- assigns.memory_samples, do: Game.LiveMemory.total_bytes(sample))

    {sample_bytes, sample_count} =
      if count > 0, do: {bytes, count}, else: {assigns.last_memory_bytes, 1}

    assigns =
      assign(assigns,
        memory_total: bytes,
        memory_count: count,
        memory_capacity:
          if sample_bytes do
            for {label, mib} <- [{"256 MiB", 256}, {"1 GiB", 1024}, {"4 GiB", 4096}] do
              {label, div(mib * 1024 * 1024 * sample_count, sample_bytes)}
            end
          end
      )

    ~H"""
    <main class="game-debug" data-paused={to_string(Map.get(@game, :paused, false))}>
      <header>
        <h1>Frontier game inspector</h1>
        <button
          id="pause-game"
          type="button"
          phx-click="pause_game"
          aria-pressed={to_string(Map.get(@game, :paused, false))}
        >
          {if Map.get(@game, :paused, false), do: "Resume game", else: "Pause game"}
        </button>
        <button
          id="step-game"
          type="button"
          phx-click="step_game"
          disabled={!Map.get(@game, :paused, false)}
        >Step 100 ms</button>
        <button type="button" phx-click="reset_game">Reset game</button>
        <p>Process <code>{inspect(@game_server)}</code> · Tick <b id="game-tick">{@game.tick}</b></p>
      </header>
      <div class="debug-columns">
        <section class="debug-map" aria-label="Full game map">
          <div class="map-scene debug-scene">
            <FogOfWarFrontierWeb.MapTerrain.terrain
              places={for lat <- 0..3, lon <- 0..3, do: {lat, lon}}
              current={@square}
            />
            <div
              :for={{lat, lon} <- for(lat <- 0..3, lon <- 0..3, do: {lat, lon})}
              class={"entity-layer debug-entities at-#{lat}-#{lon}"}
            >
              <span :for={player <- occupants(@game, {lat, lon})} class="entity-slot">
                <button
                  type="button"
                  phx-click="entity"
                  phx-value-id={player.id}
                  class={[
                    "entity-sprite entity-player debug-entity",
                    player.health <= 0 && "debug-dead"
                  ]}
                  aria-label={"Inspect player #{player.id}"}
                  title={"#{player.id} · #{player.health} HP"}
                ></button>
              </span>
              <span
                :if={@game.monster.mode != :banished && @game.monster.position == {lat, lon}}
                class="entity-slot"
              >
                <button
                  type="button"
                  phx-click="monster"
                  class={[
                    "entity-sprite entity-monster debug-entity",
                    "monster-#{@game.monster.mode}"
                  ]}
                  aria-label="Inspect Split Brain beast"
                  title="Split Brain beast"
                ></button>
              </span>
            </div>
            <div class="debug-map-labels" aria-hidden="true">
              <span
                :for={{lat, lon} <- for(lat <- 0..3, lon <- 0..3, do: {lat, lon})}
                class={"debug-map-label at-#{lat}-#{lon}"}
              >
                <small>{lat},{lon}</small>
                <strong :if={occupants(@game, {lat, lon}) != []} class="debug-player-count">{length(
                  occupants(@game, {lat, lon})
                )}</strong>
                <i
                  :if={@game.monster.mode != :banished && @game.monster.position == {lat, lon}}
                  class="debug-monster"
                ></i>
              </span>
            </div>
            <div class="travel-layer">
              <button
                :for={{lat, lon} <- for(lat <- 0..3, lon <- 0..3, do: {lat, lon})}
                type="button"
                class={"tile-target debug-tile at-#{lat}-#{lon}"}
                phx-click="square"
                phx-value-lat={lat}
                phx-value-lon={lon}
                aria-label={"Inspect square #{lat}, #{lon}"}
              >
                <span class="sr-only">Inspect square {lat}, {lon}</span>
              </button>
            </div>
          </div>
        </section>
        <section class="debug-data">
          <section id="live-memory" class="debug-panel" aria-label="Memory by tab">
            <h2>Memory by tab</h2>
            <p>
              <b id="live-memory-total">{memory_size(@memory_total)}</b>
              total · {@memory_count} connected tabs
            </p>
            <p :if={@memory_capacity} id="live-memory-capacity">
              <b>Estimated tabs by RAM</b>
              <span :for={{label, count} <- @memory_capacity}> · {label}: {count}</span>
              <span :if={@memory_count == 0}> · last sample</span>
            </p>
            <p>
              LiveView and WebSocket process memory, sampled each second. Excludes the game server, ETS, shared binaries and OS socket buffers. Reports expire after 3 seconds.
            </p>
            <table>
              <thead>
                <tr>
                  <th>Player</th><th>Tab transport</th><th>LiveView</th><th>WebSocket</th><th>
                    Total
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{id, sample} <- Enum.sort(@memory_samples)} data-memory-tab={id}>
                  <td>{sample.player_id}</td>
                  <td>{id}</td>
                  <td title={"#{sample.messages} LiveView mailbox messages"}>
                    {memory_size(sample.bytes)}
                  </td>
                  <td>{if sample.socket_bytes, do: memory_size(sample.socket_bytes), else: "—"}</td>
                  <td>{memory_size(Game.LiveMemory.total_bytes(sample))}</td>
                </tr>
              </tbody>
            </table>
          </section>
          <section class="debug-panel debug-roster">
            <h2>Players</h2>
            <ul id="debug-players">
              <li :for={{id, player} <- Enum.sort(@game.players)}>
                <button type="button" phx-click="player" phx-value-id={id}>{id}</button>
                {inspect(player.position)} · {player.health} HP · {player.connected_views} views
              </li>
            </ul>
          </section>
          <section class="debug-panel debug-selection">
            <h2>Square {inspect(@square)}</h2>
            <p>Terrain · grass and dirt · Pines {length(GameMap.trees(@square))}</p>
            <p :if={occupants(@game, @square) == []}>No players</p>
            <div :if={@game.monster.position == @square} class="debug-monster-detail">
              <p>
                Split Brain beast · {@game.monster.mode} · {Map.get(@game.monster, :health, 200)} HP · last move tick {@game.monster.last_move_tick}
              </p>
              <pre :if={@selected == :monster}>{inspect(@game.monster, pretty: true)}</pre>
              <img
                src="/images/monster/256/monster-idle.png"
                width="256"
                height="256"
                alt="Split Brain beast"
              />
            </div>
            <pre
              :for={player <- occupants(@game, @square)}
              data-player-detail={player.id}
              class={@selected == player.id && "selected"}
            >{inspect(Map.from_struct(player), pretty: true)}</pre>
          </section>
          <section class="debug-panel debug-actions">
            <h2>Recent actions</h2>
            <pre id="game-events">{Enum.map_join(@game.recent, "\n", &inspect(&1, pretty: false, limit: :infinity))}</pre>
          </section>
        </section>
      </div>
    </main>
    """
  end
end
