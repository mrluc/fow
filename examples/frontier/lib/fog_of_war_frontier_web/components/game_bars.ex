defmodule FogOfWarFrontierWeb.GameBars do
  use Phoenix.Component
  alias FogOfWarFrontier.Game.Rules

  def bars(assigns) do
    assigns =
      assign(assigns,
        rules: Rules.client(),
        move_recharge_ms: Rules.move_recharge_ms(),
        health_max: Rules.health_max()
      )

    ~H"""
    <section
      id="frontier-bars"
      class="frontier-bars"
      aria-label="Player status"
      data-move-recharge-ms={@move_recharge_ms}
      data-health-max={@health_max}
      data-game-rules={Jason.encode!(@rules)}
    >
      <nav class="frontier-help-links" aria-label="About Frontier">
        <button
          type="button"
          class="paper-modal-trigger frontier-display"
          data-paper-open="demo-modal"
        >What is this place?</button>
        <button type="button" class="paper-modal-trigger frontier-display" data-paper-open="fow-modal">What is the Fog of War?</button>
      </nav>
      <div class="lives-row">
        <span>Lives</span><output data-lives-count>{@rules.initial_lives}</output><span
          id="frontier-life-icons"
          phx-update="ignore"
          data-lives-icons
          aria-hidden="true"
        ><img
          :for={_ <- 1..@rules.initial_lives}
          src="/images/scout/256/scout-idle.png"
          alt=""
        /></span>
      </div>
      <label class="move-bar">Move<progress data-bar="move" max="100" value="100">100%</progress></label>
      <label class="health-bar">Health<progress
        data-bar="health"
        max={@health_max}
        value={@health_max}
      >100%</progress></label>
      <label class="connection-bar"><span data-connection-label>Offline time</span><progress
        data-bar="connection"
        max="100"
        value="0"
      >Disconnected</progress></label>
    </section>
    <div id="frontier-slay-notice" role="status" phx-update="ignore"></div>
    <aside id="frontier-death" class="frontier-death" hidden role="status" aria-live="polite">
      <strong data-death-title>You died</strong><span data-death-detail></span>
    </aside>
    """
  end
end
