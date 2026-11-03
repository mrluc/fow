defmodule FogOfWarFrontierWeb.MapLive do
  use FogOfWarFrontierWeb, :live_view

  def path(lat, lon), do: "/lat/#{lat}/lon/#{lon}"

  def neighbors(lat, lon) do
    for y <- 0..3, x <- 0..3, max(abs(y - lat), abs(x - lon)) == 1, do: {y, x}
  end

  def mount(_, _, socket), do: {:ok, assign(socket, lat: 0, lon: 0, reports: 0)}

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
  def handle_event("survey", _, socket), do: {:noreply, update(socket, :reports, &(&1 + 1))}

  def render(assigns) do
    ~H"""
    <FogOfWar.region :if={assigns[:path]} id="frontier-map" path={@path} class="frontier">
      <header class="command-bar">
        <a
          href="/lat/0/lon/0"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="game-logo"
          aria-label="Fog of War · return to camp"
        ></a>
        <div class="expedition">
          <strong>THE GREEN MARCH</strong><span>EXPEDITION 01 / 16 LOCATIONS</span>
        </div>
      </header>
      <main class="command-center">
        <section class="map-console" aria-labelledby="map-heading">
          <header class="console-heading">
            <h1 id="map-heading">The eastern valley</h1><span>LAT {@lat} / LON {@lon}</span>
          </header>
          <div class="map-viewport">
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
                  <div class="screen-fog"></div>
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
              <nav class="labels-layer" aria-label="Map locations">
                <div
                  :for={{lat, lon} <- @places}
                  class={[
                    "place-label fow-nav",
                    "at-#{lat}-#{lon}",
                    {lat, lon} == {@lat, @lon} && "current"
                  ]}
                  data-fog-of-war-to={path(lat, lon)}
                >
                  <.link
                    :if={{lat, lon} in @neighbors}
                    navigate={path(lat, lon)}
                    class="location-link"
                    aria-label={"Travel to #{lat}, #{lon}"}
                  ><span>{lat} / {lon}</span></.link>
                  <span :if={{lat, lon} not in @neighbors} class="location-name">{lat} / {lon}</span>
                </div>
              </nav>
            </div>
          </div>
          <footer class="map-key">
            <span><i class="key-live"></i> HERE</span><span><i class="key-known"></i> EXPLORED</span><span><i class="key-dark"></i>
            UNKNOWN</span>
          </footer>
        </section>
        <aside class="orders">
          <p class="overline">FIELD JOURNAL</p>
          <h2 id="sector-name">
            {if @lat == 0 and @lon == 0, do: "Base camp", else: "The green march"}
          </h2>
          <p class="coordinates">LAT {@lat} · LON {@lon}</p>
          <p class="sector-description">
            Grass, earth and pine. Follow the edge of the clearing; each step reveals another patch of the valley.
          </p>
          <p class="overline routes-heading">NEIGHBORING GROUND</p>
          <nav class="trail-list" aria-label="Available trails">
            <.link :for={{lat, lon} <- @neighbors} navigate={path(lat, lon)} class="trail fow-nav"><span>{lat} / {lon}</span><span aria-hidden="true">↗</span></.link>
          </nav>
          <button id="survey" phx-click="survey">Survey clearing <span>+1</span></button>
          <p class="report-line">Field reports <output id="reports">{@reports}</output></p>
          <p class="field-note">
            The three clearings beside camp are charted before departure. Beyond them, the map is yours to discover.
          </p>
        </aside>
      </main>
    </FogOfWar.region>
    <FogOfWar.dev_tools socket={@socket} />
    """
  end
end
