defmodule FogOfWarBasicWeb.ProfileLive do
  use FogOfWarBasicWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.site socket={@socket} user_id={@demo_user} require_user_id>
      <.link navigate={~p"/"} class="back-link fow-nav">‹ Back</.link>
      <h1>Profile</h1>
      <p :if={@demo_user} id="private-profile">
        This is the private profile for {String.capitalize(@demo_user)}.
      </p>
      <FogOfWar.logout>
        <.form for={%{}} action={~p"/demo/logout"} method="delete">
          <button type="submit" class="account-button">Log out</button>
        </.form>
      </FogOfWar.logout>
    </Layouts.site>
    """
  end
end
