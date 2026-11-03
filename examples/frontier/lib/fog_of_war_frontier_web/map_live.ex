defmodule FogOfWarFrontierWeb.MapLive do
  use FogOfWarFrontierWeb, :live_view

  def path(lat, lon), do: "/lat/#{lat}/lon/#{lon}"

  def neighbors(lat, lon) do
    for y <- 0..3, x <- 0..3, max(abs(y - lat), abs(x - lon)) == 1, do: {y, x}
  end

  def mount(_, _, socket), do: {:ok, assign(socket, lat: 0, lon: 0)}

  def handle_params(%{"lat" => lat, "lon" => lon}, _, socket) do
    with {y, ""} <- Integer.parse(lat),
         {x, ""} <- Integer.parse(lon),
         true <- y in 0..3 and x in 0..3 do
      {:noreply,
       assign(socket,
         lat: y,
         lon: x,
         path: path(y, x),
         places: for(a <- 0..3, b <- 0..3, do: {a, b}),
         neighbors: neighbors(y, x)
       )}
    else
      _ -> {:noreply, push_navigate(socket, to: path(0, 0))}
    end
  end

  def handle_params(_, _, socket), do: {:noreply, push_navigate(socket, to: path(0, 0))}

  def render(assigns) do
    ~H"""
    <FogOfWar.region :if={assigns[:path]} id="frontier-map" path={@path} class="frontier">
      <div class="game-logo" role="img" aria-label="Fog of War"></div>
      <main class="map-viewport" aria-label="The valley">
        <div id="map-scene" class="map-scene" data-lat={@lat} data-lon={@lon}>
          <div class="ground-layer" aria-hidden="true">
            <div
              :for={{lat, lon} <- @places}
              class={[
                "sector fow-nav",
                "at-#{lat}-#{lon}",
                {lat, lon} == {@lat, @lon} && "current"
              ]}
              data-fog-of-war-to={path(lat, lon)}
            >
              <div class="floor">
                <span :for={tile <- 0..8} class={"terrain-tile tile-#{tile}"}></span>
              </div>
            </div>
          </div>
          <div class="objects-layer" aria-hidden="true">
            <div
              :for={{lat, lon} <- @places}
              class={[
                "object fow-nav",
                "at-#{lat}-#{lon}",
                {lat, lon} == {@lat, @lon} && "current"
              ]}
              data-fog-of-war-to={path(lat, lon)}
            >
              <span :if={rem(lat + lon, 3) != 0} class="tree"></span>
              <span :if={rem(lat * 3 + lon, 4) == 0} class="tree second-tree"></span>
            </div>
          </div>
          <span id="player" class={"scout at-#{@lat}-#{@lon}"} aria-label="Your scout"></span>
          <nav class="travel-layer" aria-label="Travel to a neighboring tile">
            <.link
              :for={{lat, lon} <- @neighbors}
              navigate={path(lat, lon)}
              class={"tile-target fow-nav at-#{lat}-#{lon}"}
              aria-label={"Travel to #{lat}, #{lon}"}
            ><span aria-hidden="true"></span></.link>
          </nav>
        </div>
      </main>
    </FogOfWar.region>
    <FogOfWar.dev_tools socket={@socket} semi_transparent={true} />
    """
  end
end
