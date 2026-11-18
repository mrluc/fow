defmodule FogOfWarTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  test "all spellings render the same explicit opt-in and escape content" do
    assigns = %{
      id: "public-region",
      path: "/notes",
      inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "<not-script>" end}]
    }

    for module <- [FogOfWar, FoW] do
      html = render_component(&module.region/1, assigns)
      assert html =~ ~s(phx-hook="FogOfWar")
      assert html =~ ~s(data-fog-of-war-path="/notes")
      assert html =~ "&lt;not-script&gt;"
      assert module.assets_path() == FogOfWar.assets_path()
    end
  end
end
