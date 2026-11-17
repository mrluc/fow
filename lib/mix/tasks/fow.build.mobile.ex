defmodule Mix.Tasks.Fow.Build.Mobile do
  use Mix.Task

  @shortdoc "Build a signed mobile release artifact"
  @moduledoc """
  Build a signed release from a generated mobile project, using Mob's signing
  configuration. Android produces an AAB and iOS produces an IPA.

      mix fow.build.mobile --platform android --output .fow/android-dev/projects/mobile

  Run from the Phoenix project. For a development build on a device, use
  `mix fow.mobile`, which uses Mob's development deploy workflow.
  """

  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [manifest: :string, env: :string, output: :string, platform: :string]
      )

    platform = opts[:platform] || "android"

    if rest != [] || invalid != [] || platform not in ["android", "ios"],
      do:
        Mix.raise("Expected --platform android or ios and optional --output, --manifest or --env")

    project = FogOfWar.Wrapper.Workflow.project_path(opts[:manifest] || ".fow.json", :mob, opts)

    unless File.regular?(Path.join(project, "mob.exs")),
      do: Mix.raise("Generate the mobile project first: #{project}")

    for arguments <- [["deps.get"], ["mob.install"], ["mob.release", "--" <> platform]] do
      {_, status} =
        System.cmd("mix", arguments,
          cd: project,
          into: IO.stream(:stdio, :line),
          stderr_to_stdout: true
        )

      if status != 0, do: Mix.raise("mix #{hd(arguments)} exited with status #{status}")
    end
  end
end
