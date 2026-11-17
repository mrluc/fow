defmodule FogOfWarBasicWeb.LoginLive do
  use FogOfWarBasicWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.site socket={@socket} cache={false}>
      <section class="login-card">
        <.link navigate={~p"/"} class="back-link">‹ Back</.link>
        <h1>Log in</h1>
        <p>Choose a demo account.</p>
        <.form for={%{}} action={~p"/demo/login"} method="post">
          <button class="account-button" name="name" value="bob">Log in as Bob</button>
          <button class="account-button" name="name" value="sally">Log in as Sally</button>
        </.form>
      </section>
    </Layouts.site>
    """
  end
end
