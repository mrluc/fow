defmodule FogOfWar.DevToolsTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.Socket

  setup do
    previous = Application.fetch_env(:fow, :dev_tools)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:fow, :dev_tools, value)
        :error -> Application.delete_env(:fow, :dev_tools)
      end
    end)
  end

  test "developer tools are opt-in, and explicit false overrides the package setting" do
    Application.delete_env(:fow, :dev_tools)
    assert String.trim(render_component(&FogOfWar.dev_tools/1, socket: nil)) == ""
    Application.put_env(:fow, :dev_tools, true)
    assert String.trim(render_component(&FogOfWar.dev_tools/1, socket: nil, enabled: false)) == ""
  end

  test "scale defaults to one and renders a positive component setting as a CSS variable" do
    {:ok, default, _} = FogOfWar.DevToolsLive.mount(%{}, %{}, %Socket{})
    assert default.assigns.scale == 1.0

    {:ok, scaled, _} =
      FogOfWar.DevToolsLive.mount(%{}, %{"scale" => 0.9}, %Socket{})

    html = render_component(&FogOfWar.DevToolsLive.render/1, scaled.assigns)
    assert html =~ "--fog-of-war-dev-tools-scale: 0.9;"

    for invalid <- [0, -1, "small"] do
      assert_raise ArgumentError, fn ->
        FogOfWar.DevToolsLive.mount(%{}, %{"scale" => invalid}, %Socket{})
      end
    end
  end
end
