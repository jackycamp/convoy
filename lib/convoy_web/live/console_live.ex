defmodule ConvoyWeb.ConsoleLive do
  @moduledoc """
  The app's main Phoenix LiveView. 
  Allows one to spin up and spin down elixir nodes, 
  and interact with their shells, in a railway environment.
  """

  use ConvoyWeb, :live_view
  alias Convoy.Railway
  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex flex-wrap justify-center gap-2">
        <%= for {node_name, node} <- @nodes do %>
          {live_render(@socket, ConvoyWeb.ShellLive,
            id: "node-shell-#{node_name}",
            session: %{
              "node" => node
            }
          )}
        <% end %>
      </div>

      <div class="flex justify-center mt-12">
        <div
          class="bg-bubblegum-pink flex items-center justify-center p-2 sm:p-4 rounded-full border-2 border-zinc-700 cursor-pointer hover:bg-light-plum"
          phx-click="launch_node"
        >
          <.icon name="hero-rocket-launch" class="text-zinc-900" />
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Convoy.PubSub, "nodes")

    nodes = Railway.get_nodes()

    {:ok,
     assign(socket,
       nodes: nodes
     )}
  end

  @impl true
  def handle_event("launch_node", _params, socket) do
    if length(Map.keys(socket.assigns.nodes)) >= 5 do
      # FIXME: flash message of at cluster limit or something
      Logger.info("at cluster limit, cannot add more nodes!")
      {:noreply, socket}
    else
      name = "convoy-#{shortid()}"
      Task.start(fn -> Railway.launch_node(name) end)

      node =
        Convoy.Node.with_name(name)
        |> Convoy.Node.set_status("creating service")

      nodes = Map.put(socket.assigns.nodes, name, node)
      {:noreply, assign(socket, nodes: nodes)}
    end
  end

  @impl true
  def handle_info({:add_node, node}, socket) do
    nodes = Map.put(socket.assigns.nodes, node["id"], node)
    {:noreply, assign(socket, nodes: nodes)}
  end

  @impl true
  def handle_info({:del_node, id}, socket) do
    nodes = Map.delete(socket.assigns.nodes, id)
    {:noreply, assign(socket, nodes: nodes)}
  end

  defp shortid() do
    :crypto.strong_rand_bytes(3)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 4)
    |> String.downcase()
  end
end
