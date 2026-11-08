defmodule FogOfWarFrontier.InspectorAuthTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint FogOfWarFrontierWeb.Endpoint
  @app :fog_of_war_frontier

  setup do
    old = Application.get_env(@app, :inspector)
    dev = Application.get_env(@app, :dev_routes)
    Application.put_env(@app, :dev_routes, false)

    Application.put_env(@app, :inspector,
      enabled: true,
      username: "admin",
      password: "test-password"
    )

    on_exit(fn ->
      if old,
        do: Application.put_env(@app, :inspector, old),
        else: Application.delete_env(@app, :inspector)

      Application.put_env(@app, :dev_routes, dev)
    end)
  end

  test "production inspector fails closed without explicit enabled credentials" do
    for config <- [[], [enabled: true], [enabled: false, password: "test-password"]] do
      Application.put_env(@app, :inspector, config)
      assert get(build_conn(), "/dev/game").status == 404
    end
  end

  test "missing or wrong credentials are challenged; correct credentials mount LiveView" do
    assert get(build_conn(), "/dev/game").status == 401

    wrong =
      Plug.Conn.put_req_header(
        build_conn(),
        "authorization",
        Plug.BasicAuth.encode_basic_auth("admin", "wrong")
      )

    assert get(wrong, "/dev/game").status == 401

    conn =
      Plug.Conn.put_req_header(
        build_conn(),
        "authorization",
        Plug.BasicAuth.encode_basic_auth("admin", "test-password")
      )

    {:ok, view, _} = live(conn, "/dev/game")
    assert has_element?(view, "#pause-game")
  end

  test "socket mount rejects missing proof, disabled access, and old credentials" do
    alias FogOfWarFrontierWeb.InspectorAuth
    assert {:halt, _} = InspectorAuth.on_mount(:default, %{}, %{}, %Phoenix.LiveView.Socket{})

    conn =
      build_conn()
      |> Plug.Conn.put_req_header(
        "authorization",
        Plug.BasicAuth.encode_basic_auth("admin", "test-password")
      )
      |> get("/dev/game")

    session = Plug.Conn.get_session(conn)
    assert {:cont, _} = InspectorAuth.on_mount(:default, %{}, session, %Phoenix.LiveView.Socket{})
    Application.put_env(@app, :inspector, enabled: true, password: "changed-password")
    assert {:halt, _} = InspectorAuth.on_mount(:default, %{}, session, %Phoenix.LiveView.Socket{})
    Application.put_env(@app, :inspector, [])
    assert {:halt, _} = InspectorAuth.on_mount(:default, %{}, session, %Phoenix.LiveView.Socket{})
  end
end
