defmodule FogOfWarFrontierWeb.BrowserFixture do
  import Plug.Conn
  alias FogOfWarFrontier.Game

  def init(opts), do: opts

  def call(%{method: "POST", path_info: ["__browser", "monster", mode]} = conn, _)
      when mode in ["disable", "enable"] do
    if Application.get_env(:fog_of_war_frontier, :browser_fixtures, false) do
      mode = if mode == "disable", do: :disabled, else: :idle
      :sys.replace_state(Game, fn state -> put_in(state.game.monster.mode, mode) end)
      conn |> send_resp(204, "") |> halt()
    else
      conn
    end
  end

  def call(conn, _), do: conn
end
