defmodule CountersMobile.HomeScreenTest do
  use Mob.ScreenCase, async: false
  setup do
    start_supervised!(CountersMobile.PublicShell)
    :ok
  end
  test "starts with the bundled public site and renders a native WebView" do
    view = mount_screen(CountersMobile.HomeScreen)
    assert assigns(view).url =~ "http://127.0.0.1:"
    assert "http://127.0.0.1:47180/" in assigns(view).allowed
    assert_renderable(view)
  end
end
