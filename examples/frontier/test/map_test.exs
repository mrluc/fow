defmodule FogOfWarFrontier.MapTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint FogOfWarFrontierWeb.Endpoint
  test "only adjacent sectors have travel links; survey is a real server event" do
    {:ok, view, _} = live(build_conn(), "/")
    assert has_element?(view, "#sector-name", "Base camp")
    assert has_element?(view, "a[href='/sectors/woods']")
    refute has_element?(view, "a[href='/sectors/watch']")
    view |> element("#survey") |> render_click()
    assert has_element?(view, "#reports", "1")

    {:ok, woods, _} =
      view
      |> element(".trail[href='/sectors/woods']")
      |> render_click()
      |> follow_redirect(build_conn(), "/sectors/woods")

    assert has_element?(woods, "#sector-name", "Pinewood")
    assert has_element?(woods, "a[href='/sectors/quarry']")
    refute has_element?(woods, "a[href='/sectors/mill']")
  end
end
