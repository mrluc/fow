defmodule FogOfWarBasicWeb.CounterLive do
  use FogOfWarBasicWeb, :live_view

  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) && FogOfWarBasic.Counters.known?(id),
      do: FogOfWarBasic.Counters.subscribe(id)

    {:ok, socket}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    if FogOfWarBasic.Counters.known?(id) do
      {:noreply,
       assign(socket,
         id: id,
         label: FogOfWarBasic.Counters.label(id),
         count: FogOfWarBasic.Counters.get(id)
       )}
    else
      {:noreply, push_navigate(socket, to: ~p"/")}
    end
  end

  def handle_event("increment", _params, socket) do
    count = FogOfWarBasic.Counters.increment(socket.assigns.id)

    socket =
      if socket.assigns.demo_user && count == 100,
        do: push_event(socket, "fow:logout", %{}),
        else: socket

    {:noreply, assign(socket, :count, count)}
  end

  def handle_info({:counter_changed, id, count}, socket) do
    if socket.assigns.id == id,
      do: {:noreply, assign(socket, :count, count)},
      else: {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.site socket={@socket} user_id={@demo_user}>
      <.link navigate={~p"/"} class="back-link fow-nav">‹ Back</.link>
      <section class="counter-card" aria-labelledby="counter-title">
        <p :if={@demo_user} class="counter-greeting">
          Hi <.link navigate={~p"/profile"} class={"profile-name fow-nav #{@demo_user}"}>{String.capitalize(@demo_user)}</.link>! Here’s your counter.
        </p>
        <h1 id="counter-title">{@label}</h1>
        <output id="count" aria-live="polite">{@count}</output>
        <p :if={@demo_user}>If your increment reaches 100, you’ll be signed out.</p>
        <button id="increment-counter" phx-click="increment">Increment</button>
      </section>
    </Layouts.site>
    """
  end
end
