defmodule FogOfWarBasicWeb.CounterIndexLive do
  use FogOfWarBasicWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket), do: FogOfWarBasic.Counters.subscribe(:all)
    {:ok, assign(socket, counters: FogOfWarBasic.Counters.all())}
  end

  def handle_info({:counter_changed, id, count}, socket) do
    {:noreply, update(socket, :counters, &Map.put(&1, id, count))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.site socket={@socket} user_id={@demo_user}>
      <section class="index-intro" aria-labelledby="page-title">
        <p class="eyebrow">YOUR COUNTERS</p>
        <h1 id="page-title">Counters</h1>
        <p>Choose a counter to open it.</p>
      </section>
      <ul class="counter-list" aria-label="Counters">
        <li :for={{id, count} <- Enum.sort(@counters)}>
          <.link navigate={~p"/counters/#{id}"} class="counter-link fow-nav">
            <span>{FogOfWarBasic.Counters.label(id)}</span>
            <span class="counter-value">{count}</span>
          </.link>
        </li>
      </ul>
    </Layouts.site>
    """
  end
end
