defmodule FogOfWarFrontierWeb.PlayerSession do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _) do
    if get_session(conn, :frontier_player_id) do
      conn
    else
      put_session(
        conn,
        :frontier_player_id,
        Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
      )
    end
  end
end
