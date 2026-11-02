defmodule FogOfWarFrontierWeb.MapLive do
  use FogOfWarFrontierWeb, :live_view

  @sectors [
    %{
      id: "camp",
      name: "Base camp",
      terrain: "grass",
      building: "castle",
      exits: ["woods", "mill"],
      detail: "The expedition starts here. Two trails lead into the valley."
    },
    %{
      id: "woods",
      name: "Pinewood",
      terrain: "grass",
      building: "pine",
      exits: ["camp", "quarry"],
      detail: "Old pines shelter the northern trail. Stone lies beyond the ridge."
    },
    %{
      id: "quarry",
      name: "Old quarry",
      terrain: "gravel",
      building: "stone",
      exits: ["woods", "watch"],
      detail: "A disused quarry. A narrow pass climbs to the watchtower."
    },
    %{
      id: "mill",
      name: "Windmill",
      terrain: "sand",
      building: "mill",
      exits: ["camp", "market"],
      detail: "Grain and shelter beside the southern road."
    },
    %{
      id: "market",
      name: "Crossroads",
      terrain: "grass",
      building: "market",
      exits: ["mill", "watch"],
      detail: "Two trade routes meet here. The watchtower guards the eastern trail."
    },
    %{
      id: "watch",
      name: "Watchtower",
      terrain: "gravel",
      building: "tower",
      exits: ["quarry", "market"],
      detail: "The far end of the valley. Both routes meet beneath the tower."
    }
  ]
  defp sector_path("camp"), do: "/"
  defp sector_path(id), do: "/sectors/#{id}"

  def mount(_, _, socket), do: {:ok, assign(socket, reports: 0)}

  def handle_params(params, _, socket) do
    sector = Enum.find(@sectors, &(&1.id == params["id"])) || hd(@sectors)

    {:noreply,
     assign(socket,
       sector: sector,
       sectors: @sectors,
       path: if(params["id"], do: "/sectors/#{sector.id}", else: "/")
     )}
  end

  def handle_event("survey", _, socket), do: {:noreply, update(socket, :reports, &(&1 + 1))}

  def render(assigns) do
    ~H"""
    <FogOfWar.region id="frontier-map" path={@path} class="frontier">
      <header class="command-bar">
        <div>
          <span class="signal-light"></span>
          FRONTIER <span class="command-subtitle">/ RECONNAISSANCE</span>
        </div>
        <span>EXPEDITION 01</span>
      </header>
      <main class="command-center">
        <section class="map-console" aria-labelledby="map-heading">
          <header class="console-heading">
            <h1 id="map-heading">The eastern valley</h1><span>06 SECTORS</span>
          </header>
          <div class="map-viewport">
            <div class="island">
              <div
                :for={{place, index} <- Enum.with_index(@sectors)}
                class={[
                  "sector fow-nav",
                  "sector-#{index}",
                  place.id == @sector.id && "current-sector"
                ]}
                data-fog-of-war-to={sector_path(place.id)}
              >
                <div class={["terrain", place.terrain]}>
                  <span class={["structure", place.building]}></span>
                </div>
                <.link
                  :if={place.id in @sector.exits}
                  navigate={sector_path(place.id)}
                  class="sector-target"
                  aria-label={"Travel to #{place.name}"}
                ><span>{place.name}</span></.link>
                <span
                  :if={place.id not in @sector.exits}
                  class="sector-target blocked"
                  aria-label={"#{place.name}: no direct trail"}
                ><span>{place.name}</span></span>
                <span :if={place.id == @sector.id} class="scout" aria-label="Your scout"></span>
              </div>
            </div>
          </div>
          <footer class="map-key">
            <span><i class="key-live"></i> HERE</span><span><i class="key-known"></i> EXPLORED</span><span><i class="key-dark"></i>
            UNKNOWN</span>
          </footer>
        </section>
        <aside class="orders" aria-labelledby="sector-name">
          <p class="overline">SECTOR REPORT</p>
          <h2 id="sector-name">{@sector.name}</h2>
          <p class="sector-description">{@sector.detail}</p>
          <p class="overline routes-heading">AVAILABLE TRAILS</p>
          <nav class="trail-list" aria-label="Available trails">
            <.link
              :for={place <- Enum.filter(@sectors, &(&1.id in @sector.exits))}
              navigate={sector_path(place.id)}
              class="trail fow-nav"
            ><span>{place.name}</span><span aria-hidden="true">→</span></.link>
          </nav>
          <button id="survey" phx-click="survey">Survey sector <span>+1</span></button>
          <p class="report-line">Field reports <output id="reports">{@reports}</output></p>
          <p class="field-note">
            Follow a trail to explore. Revisit known ground when contact is lost.
          </p>
        </aside>
      </main>
    </FogOfWar.region>
    <FogOfWar.dev_tools socket={@socket} />
    """
  end
end
