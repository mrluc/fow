defmodule FogOfWarFrontierWeb.MapScene do
  use Phoenix.Component

  def scene(assigns) do
    assigns =
      assigns
      |> assign_new(:multiplayer, fn -> false end)
      |> assign_new(:route_prefix, fn -> "" end)

    ~H"""
    <FogOfWar.region :if={assigns[:path]} id="frontier-map" path={@path} class="frontier">
      <div class="game-logo" role="img" aria-label="Fog of War"></div>
      <main class="map-viewport" aria-label="The valley">
        <div id="map-scene" class="map-scene" data-lat={@lat} data-lon={@lon}>
          <FogOfWarFrontierWeb.MapTerrain.terrain
            places={@places}
            current={{@lat, @lon}}
            fog_prefix={@route_prefix}
            streamed={@multiplayer}
            tiles={if @multiplayer, do: @streams.tiles}
            objects={if @multiplayer, do: @streams.objects}
          />
          <div
            :if={@multiplayer}
            id="multi-entities"
            phx-update="stream"
            phx-hook="FrontierEntities"
            class={"entity-layer at-#{@lat}-#{@lon}"}
          >
            <span
              :for={{dom_id, entity} <- @streams.entities}
              id={dom_id}
              class="entity-slot"
              data-health={entity[:health]}
            >
              <span
                class={[
                  "entity-sprite",
                  "entity-#{entity.kind}",
                  entity[:mode] && "monster-#{entity.mode}"
                ]}
                role="img"
                aria-label={
                  if entity.kind == :monster, do: "Split Brain beast", else: "Another player"
                }
              ></span>
            </span>
          </div>
          <span
            id="player"
            phx-hook={if @multiplayer, do: "FrontierPlayer"}
            data-health={assigns[:player_state] && @player_state.health}
            class={"scout at-#{@lat}-#{@lon}"}
            aria-label="Your scout"
          ></span>
          <nav class="travel-layer" aria-label="Travel to a neighboring tile">
            <.link
              :for={{lat, lon} <- @neighbors}
              navigate={if !@multiplayer, do: "#{@route_prefix}/lat/#{lat}/lon/#{lon}"}
              patch={if @multiplayer, do: "#{@route_prefix}/lat/#{lat}/lon/#{lon}"}
              class={"tile-target fow-nav at-#{lat}-#{lon}"}
              aria-label={"Travel to #{lat}, #{lon}"}
            ><span aria-hidden="true"></span></.link>
          </nav>
        </div>
      </main>
    </FogOfWar.region>
    <FogOfWar.dev_tools socket={@socket} enabled={true} dock="bottom-right" semi_transparent={true} scale={1.1} />
    """
  end
end
