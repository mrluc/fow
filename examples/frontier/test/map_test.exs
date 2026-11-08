defmodule FogOfWarFrontier.MapTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint FogOfWarFrontierWeb.Endpoint
  test "4 by 4 map, nine terrain tiles per location, corner start and adjacent travel" do
    {:ok, view, _} =
      live(
        Plug.Conn.put_private(build_conn(), :live_view_connect_info, %{
          session: %{"frontier_player_id" => "map-test-player"}
        }),
        "/lat/0/lon/0"
      )

    assert has_element?(view, "#player.at-0-0")

    refute has_element?(
             view,
             "#frontier-map header, #frontier-map aside, #frontier-map footer, #frontier-map h1, #frontier-map h2"
           )

    for path <- ["/lat/0/lon/1", "/lat/1/lon/0", "/lat/1/lon/1"],
        do: assert(has_element?(view, "a[href='#{path}']"))

    refute has_element?(view, "a[href='/lat/3/lon/3']")

    assert view
           |> render()
           |> Floki.parse_document!()
           |> Floki.find(".ground-layer .sector")
           |> length() == 16

    assert view |> render() |> Floki.parse_document!() |> Floki.find(".terrain-tile") |> length() ==
             144

    {:ok, next, _} =
      view
      |> element(".tile-target[href='/lat/1/lon/1']")
      |> render_click()
      |> follow_redirect(
        Plug.Conn.put_private(build_conn(), :live_view_connect_info, %{
          session: %{"frontier_player_id" => "map-test-player"}
        }),
        "/lat/1/lon/1"
      )

    assert has_element?(next, "#player.at-1-1")

    assert next |> render() |> Floki.parse_document!() |> Floki.find(".tile-target") |> length() ==
             8
  end

  test "root opens multiplayer; invalid legacy coordinates return to the starting corner" do
    assert {:error, {:live_redirect, %{to: "/multi/lat/0/lon/0"}}} = live(build_conn(), "/")
    assert {:error, {:live_redirect, %{to: "/lat/0/lon/0"}}} = live(build_conn(), "/lat/8/lon/8")
  end
end
