defmodule FogOfWarBasicWeb.CounterIndexLive do
  use FogOfWarBasicWeb, :live_view

  def mount(_params, _session, socket),
    do: {:ok, assign(socket, counters: FogOfWarBasic.Counters.all())}

  def render(assigns) do
    ~H"""
    <Layouts.site socket={@socket} path="/">
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
