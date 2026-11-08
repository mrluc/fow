defmodule FogOfWarFrontierWeb.InspectorAuth do
  @moduledoc "Optional HTTP Basic Auth for the inspector, checked again on LiveView mount."
  import Plug.Conn
  import Phoenix.LiveView, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _) do
    case policy() do
      :disabled ->
        conn |> send_resp(404, "Not found") |> halt()

      :development ->
        put_session(conn, :frontier_inspector, "development")

      {:basic, user, password} ->
        conn = Plug.BasicAuth.basic_auth(conn, username: user, password: password)

        if conn.halted,
          do: conn,
          else: put_session(conn, :frontier_inspector, proof(user, password))
    end
  end

  def on_mount(:default, _, session, socket) do
    expected =
      case policy() do
        :disabled -> nil
        :development -> "development"
        {:basic, user, password} -> proof(user, password)
      end

    actual = session["frontier_inspector"]

    if is_binary(expected) and is_binary(actual) and Plug.Crypto.secure_compare(expected, actual),
      do: {:cont, socket},
      else: {:halt, redirect(socket, to: "/")}
  end

  defp policy do
    config = Application.get_env(:fog_of_war_frontier, :inspector, [])
    dev = Application.get_env(:fog_of_war_frontier, :dev_routes, false)
    password = config[:password]

    cond do
      not (dev or config[:enabled] == true) ->
        :disabled

      is_binary(password) and byte_size(password) > 0 ->
        {:basic, config[:username] || "admin", password}

      dev ->
        :development

      true ->
        :disabled
    end
  end

  defp proof(user, password),
    do:
      :crypto.mac(
        :hmac,
        :sha256,
        FogOfWarFrontierWeb.Endpoint.config(:secret_key_base),
        user <> ":" <> password
      )
      |> Base.encode64()
end
