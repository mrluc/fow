defmodule FogOfWarBasicWeb.PagesTest do
  use FogOfWarBasicWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "index links to distinct counters and each counter updates", %{conn: conn} do
    {:ok, index, _html} = live(conn, "/")
    assert has_element?(index, "#counter-site[phx-hook=FogOfWar][data-fog-of-war-path='/']")
    assert has_element?(index, "#page-title", "Counters")
    assert has_element?(index, "a[href='/counters/one']", "Counter one")
    assert has_element?(index, "a[href='/counters/two']", "Counter two")

    {:ok, first, _html} =
      index
      |> element("a", "Counter one")
      |> render_click()
      |> follow_redirect(conn, "/counters/one")

    assert has_element?(
             first,
             "#counter-site[phx-hook=FogOfWar][data-fog-of-war-path='/counters/one']"
           )

    assert has_element?(first, "#counter-title", "Counter one")
    assert has_element?(first, "a.back-link[href='/']", "‹ Back")
    first |> element("button", "Increment") |> render_click()
    assert has_element?(first, "#count", "1")

    {:ok, second, _html} = live(conn, "/counters/two")
    assert has_element?(second, "#counter-title", "Counter two")
    assert has_element?(second, "#count", "0")
  end
end
