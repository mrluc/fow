defmodule FogOfWar.Wrapper.Output do
  @moduledoc """
  Stages generated files before replacing a project or installed app.
  Destination checks protect the source tree and other inputs from replacement.

  ## How it fits

  Used by `Generator` and `Workflow` to stage replacements safely. It is an implementation detail of generation and installation.
  """

  alias FogOfWar.Wrapper.Manifest

  @doc "Write a relative file under a staging directory controlled by the wrapper."
  def write_staged!(stage, relative, content) do
    target = Path.join(stage, Manifest.relative_path!(relative))
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, content)
  end

  # Build beside the destination, then swap. A failed build never deletes the
  # previous project/app. Rename first, so cleanup never traverses its old path.
  @doc "Build in a temporary sibling directory and replace the destination after success."
  def replace!(output, opts, build) do
    output = Path.expand(output)
    validate!(output, opts[:protected] || [])
    exists = File.exists?(output)

    if exists && !opts[:force],
      do: Mix.raise("Destination exists: #{output}; pass --force to replace it completely")

    token = "#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
    stage = output <> ".tmp-" <> token
    backup = output <> ".old-" <> token
    File.mkdir_p!(Path.dirname(output))
    File.mkdir!(stage)

    try do
      build.(stage)
      # Recheck immediately before replacement, including symlinks introduced
      # while generation/building ran.
      validate!(output, opts[:protected] || [])

      swap!(stage, output, backup, opts[:force])
      File.rm_rf!(backup)
      output
    after
      File.rm_rf(stage)
    end
  end

  defp swap!(stage, output, backup, force) do
    if File.exists?(output) do
      if !force, do: Mix.raise("Destination appeared during generation: #{output}")
      File.rename!(output, backup)
    end

    rename_or_restore!(stage, output, backup)
  end

  defp rename_or_restore!(stage, output, backup) do
    File.rename!(stage, output)
  rescue
    error ->
      if File.exists?(backup), do: File.rename!(backup, output)
      reraise error, __STACKTRACE__
  end

  @doc "Check a destination against protected paths before writing or replacing it."
  def validate!(output, protected) do
    output = Path.expand(output)

    if match?({:ok, %{type: :symlink}}, File.lstat(output)),
      do: Mix.raise("Refusing a symlink destination: #{output}")

    _checked_path =
      output
      |> Path.split()
      |> Enum.reduce("/", fn part, parent ->
        path = Path.join(parent, part)
        # macOS exposes these standard system aliases; user-created aliases are
        # rejected so --force never reaches through them to delete another tree.
        if match?({:ok, %{type: :symlink}}, File.lstat(path)) &&
             path not in ["/tmp", "/var", "/etc"],
           do: Mix.raise("Refusing a symlink in the destination path: #{path}")

        path
      end)

    resolved = resolve(output)
    roots = Enum.map(["/", System.user_home!() | protected], &resolve/1)

    if Enum.any?(roots, fn root ->
         resolved == root || String.starts_with?(root, resolved <> "/")
       end),
       do: Mix.raise("Refusing protected destination: #{output}")

    output
  end

  # Resolve existing parent links too, so an alias cannot bypass the protected
  # project/home checks. Missing suffixes remain ordinary path components.
  defp resolve(path), do: resolve(Path.split(Path.expand(path)), "/", 0)
  defp resolve([], path, _depth), do: path
  defp resolve(_, _, depth) when depth > 40, do: Mix.raise("Too many symlinks in output path")
  defp resolve(["/" | rest], _, depth), do: resolve(rest, "/", depth)

  defp resolve([part | rest], parent, depth) do
    path = Path.join(parent, part)

    case File.read_link(path) do
      {:ok, target} -> resolve(Path.split(Path.expand(target, parent)) ++ rest, "/", depth + 1)
      _ -> resolve(rest, path, depth)
    end
  end
end
