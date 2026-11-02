defmodule FogOfWar.DevToolsTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest

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
end
