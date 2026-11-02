defmodule FogOfWarBasicWeb.CounterLive do
  use FogOfWarBasicWeb, :live_view

  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(%{"id" => id}, _uri, socket) do
    if FogOfWarBasic.Counters.known?(id) do
      {:noreply,
       assign(socket,
         id: id,
         label: FogOfWarBasic.Counters.label(id),
         count: FogOfWarBasic.Counters.get(id),
         path: "/counters/#{id}"
       )}
    else
      {:noreply, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_event("increment", _params, socket) do
    count = FogOfWarBasic.Counters.increment(socket.assigns.id)
    {:noreply, assign(socket, :count, count)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.site socket={@socket} path={@path}>
      <.link navigate={~p"/"} class="back-link fow-nav">‹ Back</.link>
      <section class="counter-card" aria-labelledby="counter-title">
        <p class="eyebrow">COUNTER</p>
        <h1 id="counter-title">{@label}</h1>
        <output id="count" aria-live="polite">{@count}</output>
        <button id="increment-counter" phx-click="increment">Increment</button>
      </section>
    </Layouts.site>
    """
  end
end
