defmodule Mix.Tasks.Frontier.PreloadImages do
  use Mix.Task

  @shortdoc "Regenerate CSS image preloads in the root layout"

  @layout "lib/fog_of_war_frontier_web/components/layouts/root.html.heex"
  @start "<!-- frontier:css-image-preloads:start -->"
  @finish "<!-- frontier:css-image-preloads:end -->"

  @impl Mix.Task
  def run(_args) do
    css_files = Path.wildcard("priv/static/css/**/*.css")

    urls =
      css_files
      |> Enum.flat_map(fn file ->
        file
        |> File.read!()
        |> then(&Regex.scan(~r/url\(\s*['"]?(\/images\/[^)'"]+)['"]?\s*\)/, &1, capture: :all_but_first))
        |> List.flatten()
      end)
      |> Enum.uniq()
      |> Enum.sort()

    block =
      Enum.join(
        [@start, "<%!-- Regenerate with mix frontier.preload_images. --%>"] ++
          Enum.map(urls, &~s(<link rel="preload" as="image" href="#{&1}" />)) ++
          [@finish],
        "\n"
      )

    layout = File.read!(@layout)
    pattern = Regex.compile!(Regex.escape(@start) <> ".*?" <> Regex.escape(@finish), "s")

    updated =
      if Regex.match?(pattern, layout) do
        Regex.replace(pattern, layout, block)
      else
        String.replace(layout, ~r/(<link phx-track-static rel="stylesheet")/, block <> "\n    \\1")
      end

    File.write!(@layout, updated)
    Mix.shell().info("Updated CSS image preloads in #{@layout}")
  end
end
