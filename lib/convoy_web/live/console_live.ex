defmodule ConvoyWeb.ConsoleLive do
  use ConvoyWeb, :live_view
  alias Convoy.Railway
  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex flex-wrap justify-center gap-2">
        <%= for {node_id, node} <- @nodes do %>
          {live_render(@socket, ConvoyWeb.ShellLive,
            id: "node-shell-#{node_id}",
            session: %{
              "node_id" => node_id,
              "is_ctrl" => node["serviceName"] == "convoy",
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
    # TODO: on first mount, need to load nodes
    # Convoy.Railway.get_service_instances()
    # where latestDeployment.deploymentStopped is false
    # these are our currently "up nodes", need to connect them as well

    # FIXME: once we have nodes, need to render "shells" for each of them
    nodes = Railway.get_nodes()

    Logger.info("nodes: #{inspect(nodes)}")

    {:ok,
     assign(socket,
       nodes: nodes
     )}
  end

  @impl true
  def handle_event("launch_node", _params, socket) do
    # FIXME: set limit to number of nodes
    # FIXME: determine name properly
    name = "convoy3"
    Task.start(fn -> Railway.launch_node(name) end)

    {:noreply, socket}
  end
end
