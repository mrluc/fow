defmodule FogOfWarBasic.Counters do
  use Agent

  @counters %{"one" => 0, "two" => 0, "three" => 0}

  def start_link(_opts), do: Agent.start_link(fn -> @counters end, name: __MODULE__)

  def all, do: Agent.get(__MODULE__, & &1)
  def get(id), do: Agent.get(__MODULE__, &Map.get(&1, id))

  def subscribe(id), do: Phoenix.PubSub.subscribe(FogOfWarBasic.PubSub, topic(id))

  def increment(id) do
    Agent.get_and_update(__MODULE__, fn counters ->
      count = rem(Map.fetch!(counters, id) + 1, 150)

      for key <- [id, :all] do
        Phoenix.PubSub.broadcast(FogOfWarBasic.PubSub, topic(key), {:counter_changed, id, count})
      end

      {count, Map.put(counters, id, count)}
    end)
  end

  defp topic(id), do: "counter:#{id}"

  def known?(id), do: Map.has_key?(@counters, id)
  def label("one"), do: "Counter one"
  def label("two"), do: "Counter two"
  def label("three"), do: "Counter three"
end
