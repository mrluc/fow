defmodule FogOfWarFrontier.Game.LiveMemory do
  @moduledoc "One-second player LiveView process samples; no forced GC or global process scans."
  def topic(server), do: FogOfWarFrontier.Game.topic(server) <> ":live-memory"

  def sample(player_id) do
    info = Process.info(self(), [:memory, :message_queue_len])

    %{
      player_id: player_id,
      view_id: "#{node()}:#{inspect(self())}",
      bytes: info[:memory],
      messages: info[:message_queue_len]
    }
  end

  def prune(samples, now),
    do: Map.reject(samples, fn {_, sample} -> now - sample.received_at >= 3000 end)
end
