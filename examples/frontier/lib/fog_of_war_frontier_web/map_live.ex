defmodule FogOfWarFrontierWeb.MapLive do
  use FogOfWarFrontierWeb, :live_view

  def path(lat, lon), do: "/lat/#{lat}/lon/#{lon}"

  def neighbors(lat, lon) do
    for y <- 0..3, x <- 0..3, max(abs(y - lat), abs(x - lon)) == 1, do: {y, x}
  end

  def mount(_, _, socket) do
    session = if connected?(socket), do: get_connect_info(socket, :session), else: nil
    {:ok, assign(socket, lat: 0, lon: 0, player_id: session && session["frontier_player_id"])}
  end

  def handle_params(%{"lat" => lat, "lon" => lon}, _, socket) do
    with {y, ""} <- Integer.parse(lat),
         {x, ""} <- Integer.parse(lon),
         true <- y in 0..3 and x in 0..3 do
      if connected?(socket) && socket.assigns.player_id do
        FogOfWarFrontier.Game.observe(socket.assigns.player_id, self(), {y, x})
      end

      socket =
        assign(socket,
          lat: y,
          lon: x,
          path: path(y, x),
          places: for(a <- 0..3, b <- 0..3, do: {a, b}),
          neighbors: neighbors(y, x)
        )

      {:noreply, socket}
    else
      _ -> {:noreply, push_navigate(socket, to: path(0, 0))}
    end
  end

  def handle_params(_, _, socket), do: {:noreply, push_navigate(socket, to: path(0, 0))}

  def render(assigns), do: FogOfWarFrontierWeb.MapScene.scene(assigns)
end
