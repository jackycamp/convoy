defmodule Convoy.ConvoyWorker do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    IO.puts("ConvoyWorker started on node #{Node.self()}")
    {:ok, state}
  end

  def handle_info(:ping, state) do
    IO.puts("Received ping on node #{Node.self()}")
    {:noreply, state}
  end
end
