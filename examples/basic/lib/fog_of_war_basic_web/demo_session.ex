defmodule FogOfWarBasicWeb.DemoSession do
  use FogOfWarBasicWeb, :controller

  def login(conn, %{"name" => name}) when name in ["bob", "sally"] do
    conn |> configure_session(renew: true) |> put_session(:demo_user, name) |> redirect(to: ~p"/")
  end

  def login(conn, _params), do: send_resp(conn, 400, "Choose Bob or Sally")

  def logout(conn, _params) do
    conn |> configure_session(drop: true) |> redirect(to: ~p"/")
  end

  def account_scope(conn), do: known_user(get_session(conn, :demo_user))

  def require_account(conn, _opts) do
    if account_scope(conn), do: conn, else: conn |> redirect(to: ~p"/log-in") |> halt()
  end

  def on_mount(:default, _params, session, socket) do
    {:cont, Phoenix.Component.assign(socket, :demo_user, known_user(session["demo_user"]))}
  end

  def on_mount(:require_account, params, session, socket) do
    {:cont, socket} = on_mount(:default, params, session, socket)

    if socket.assigns.demo_user,
      do: {:cont, socket},
      else: {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/log-in")}
  end

  defp known_user(name) when name in ["bob", "sally"], do: name
  defp known_user(_), do: nil
end
