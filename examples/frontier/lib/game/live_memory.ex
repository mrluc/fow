defmodule FogOfWarFrontier.Game.LiveMemory do
  @moduledoc "One-second LiveView and transport process samples; no forced GC or global process scans."
  def topic(server), do: FogOfWarFrontier.Game.topic(server) <> ":live-memory"

  def sample(player_id, transport_pid) do
    info = Process.info(self(), [:memory, :message_queue_len])

    socket_bytes =
      case Process.info(transport_pid, :memory) do
        {:memory, bytes} -> bytes
        nil -> nil
      end

    %{
      player_id: player_id,
      tab_id: "#{node()}:#{inspect(transport_pid)}",
      socket_bytes: socket_bytes,
      bytes: info[:memory],
      messages: info[:message_queue_len]
    }
  end

  def total_bytes(sample), do: sample.bytes + (sample.socket_bytes || 0)

  def prune(samples, now),
    do: Map.reject(samples, fn {_, sample} -> now - sample.received_at >= 3000 end)
end
