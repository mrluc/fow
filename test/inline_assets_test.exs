defmodule FogOfWar.Wrapper.InlineAssetsTest do
  use ExUnit.Case, async: true

  alias FogOfWar.Wrapper.InlineAssets

  test "inlines classic scripts and recursive styles while preserving defer order" do
    root = Path.join(System.tmp_dir!(), "fow-inline-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "assets"))
    on_exit(fn -> File.rm_rf!(root) end)
    File.write!(Path.join(root, "assets/a.js"), "window.a = 1")
    File.write!(Path.join(root, "assets/b.js"), "window.b = 1")

    File.write!(
      Path.join(root, "assets/site.css"),
      "@import './base.css' screen; .x{background:url('./x.png')} @font-face{font-family:Display;src:url('./font.ttf')}"
    )

    File.write!(Path.join(root, "assets/base.css"), ".base{color:red}")
    File.write!(Path.join(root, "assets/font.ttf"), "test-font-bytes")

    assets =
      Map.new(
        ["a.js", "b.js", "site.css", "base.css", "x.png", "font.ttf"],
        &{"/assets/" <> &1, "assets/" <> &1}
      )

    html =
      ~s(<html><head><script defer src="/assets/a.js"></script><script src="/assets/b.js"></script><link rel="stylesheet" href="/assets/site.css"></head><body><p>ready</p></body></html>)

    result = InlineAssets.inline(html, assets, "https://example.com", root)

    assert result =~ "window.b = 1"
    assert result =~ "@media screen"
    assert result =~ "fog-of-war-assets://bundle/assets/x.png"
    assert result =~ Base.encode64("test-font-bytes")
    assert result =~ "data:font/ttf;base64,"
    refute result =~ "fog-of-war-assets://bundle/assets/font.ttf"

    assert result |> :binary.match("window.a = 1") |> elem(0) >
             result |> :binary.match("<p>ready") |> elem(0)
  end

  test "rejects external async scripts" do
    assert_raise ArgumentError, ~r/async external script is unsupported/, fn ->
      InlineAssets.inline(
        ~s(<script async src="/a.js"></script>),
        %{"/a.js" => "a.js"},
        "https://example.com",
        "."
      )
    end
  end
end
