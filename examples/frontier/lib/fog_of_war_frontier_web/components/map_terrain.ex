defmodule FogOfWarFrontierWeb.MapTerrain do
  use Phoenix.Component
  attr :places, :list, default: []
  attr :streamed, :boolean, default: false
  attr :tiles, :any, default: nil
  attr :objects, :any, default: nil
  attr :current, :any, required: true
  attr :fog_prefix, :string, default: nil

  def terrain(assigns) do
    places =
      Enum.map(assigns.places, fn {lat, lon} -> %{id: "#{lat}-#{lon}", lat: lat, lon: lon} end)

    assigns =
      assign(assigns,
        tile_rows: assigns.tiles || Enum.map(places, &{"terrain-#{&1.id}", &1}),
        object_rows: assigns.objects || Enum.map(places, &{"object-#{&1.id}", &1})
      )

    ~H"""
    <div
      id="terrain-tiles"
      phx-update={if @streamed, do: "stream"}
      class="ground-layer"
      aria-hidden="true"
    >
      <div
        :for={{dom_id, place} <- @tile_rows}
        id={dom_id}
        class={[
          "sector",
          @fog_prefix != nil && "fow-nav",
          "at-#{place.lat}-#{place.lon}",
          {place.lat, place.lon} == @current && "current"
        ]}
        data-fog-of-war-to={
          if @fog_prefix != nil, do: "#{@fog_prefix}/lat/#{place.lat}/lon/#{place.lon}"
        }
      >
        <div class="floor">
          <span :for={tile <- 0..8} class={"terrain-tile tile-#{tile}"}></span>
        </div>
      </div>
    </div>
    <div
      id="terrain-objects"
      phx-update={if @streamed, do: "stream"}
      class="objects-layer"
      aria-hidden="true"
    >
      <div
        :for={{dom_id, place} <- @object_rows}
        id={dom_id}
        class={[
          "object",
          @fog_prefix != nil && "fow-nav",
          "at-#{place.lat}-#{place.lon}",
          {place.lat, place.lon} == @current && "current"
        ]}
        data-fog-of-war-to={
          if @fog_prefix != nil, do: "#{@fog_prefix}/lat/#{place.lat}/lon/#{place.lon}"
        }
      >
        <span :if={:pine in FogOfWarFrontier.Game.Map.trees({place.lat, place.lon})} class="tree"></span>
        <span
          :if={:second_pine in FogOfWarFrontier.Game.Map.trees({place.lat, place.lon})}
          class="tree second-tree"
        ></span>
      </div>
    </div>
    """
  end
end
