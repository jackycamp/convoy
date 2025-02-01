defmodule Convoy.NodePubsub do
  def subscribe(name) when is_binary(name) do
    topic = "node:#{name}"
    Phoenix.PubSub.subscribe(Convoy.PubSub, topic)
    {:ok, topic}
  end

  def broadcast(name, msg) when is_binary(name) do
    topic = "node:#{name}"
    Phoenix.PubSub.broadcast(Convoy.PubSub, topic, msg)
    {:ok, topic}
  end
end
