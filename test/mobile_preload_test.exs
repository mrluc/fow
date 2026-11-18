defmodule FogOfWar.MobilePreloadTest do
  use ExUnit.Case, async: true

  test "native preload generation preserves long base64 chunks without Elixir inspect truncation" do
    root = Path.join(System.tmp_dir!(), "fow-preload-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    bridge = Path.join(root, "android/app/src/main/java/test/MobBridge.kt")
    File.mkdir_p!(Path.dirname(bridge))
    File.mkdir_p!(Path.join(root, "priv"))
    File.write!(bridge, "                loadUrl(url)\n")

    source =
      "window.preload = #{inspect(String.duplicate("a", 20_000), printable_limit: :infinity)};"

    File.write!(Path.join(root, "priv/fog_of_war_seed.js"), source)
    template = Application.app_dir(:fow, "priv/templates/wrapper/prepare_mobile.exs.eex")

    File.write!(
      Path.join(root, "prepare.exs"),
      EEx.eval_file(template, assigns: [origin: "https://example.com"])
    )

    {_, 0} = System.cmd(System.find_executable("elixir"), ["prepare.exs"], cd: root)
    generated = File.read!(bridge)
    refute generated =~ " <> "
    chunks = ~r/listOf\((.*?)\)\.joinToString/s |> Regex.run(generated) |> Enum.at(1)

    encoded =
      ~r/"([A-Za-z0-9+\/=]+)"/ |> Regex.scan(chunks) |> Enum.map_join(fn [_, value] -> value end)

    assert Base.decode64!(encoded) == source
    # Updating an existing marked block is also lossless and idempotent.
    {_, 0} = System.cmd(System.find_executable("elixir"), ["prepare.exs"], cd: root)
    assert File.read!(bridge) == generated
  end
end
