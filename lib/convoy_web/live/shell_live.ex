defmodule ConvoyWeb.ShellLive do
  use ConvoyWeb, :live_view
  alias Phoenix.LiveView.JS
  alias Convoy.Railway
  require Logger

  @unsafe_terms [
    "System",
    "File",
    "Port",
    "spawn",
    "Process"
    # "cookie",
    # "env"
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="text-white bg-black rounded-lg w-[30rem] h-96 font-mono text-sm xl:text-lg shadow-2xl overflow-y-auto"
      phx-click={JS.focus(to: "#node-shell-#{@node.name}-cmd-#{length(@history)}-input")}
    >
      <div class="flex justify-between text-sm bg-[#343639] py-2 px-2 mb-2">
        <div>{@node.name}</div>
        <div
          :if={!@node.control_plane? && @node.status == "SUCCESS"}
          phx-click="del_node"
          class="hover:text-gray-500 cursor-pointer"
        >
          <.icon name="hero-power" class="h-5" />
        </div>
        <div :if={@node.status == "deleting"}>
          <.icon name="hero-face-frown" class="h-5 animate-spin" />
        </div>
      </div>
      <%= for {{cmd, res}, index} <- Enum.with_index(@history) do %>
        <div class="px-2">
          <div class="flex items-center gap-2">
            <p class="text-white">iex({index})></p>
            <p class="text-white">{cmd}</p>
          </div>
          <p class={if String.contains?(res, "Error"), do: "text-red-500", else: "text-white"}>
            {res}
          </p>
        </div>
      <% end %>

      <div :if={@node.status == "SUCCESS"} class="flex items-center gap-2 px-2">
        <p class="text-white">iex({length(@history)})></p>
        <.shell_input
          id={"node-shell-#{@node.name}-cmd-#{length(@history)}-input"}
          value={@curr_command}
          onchange="check_cmd"
        />
      </div>
      <div :if={@node.status != "SUCCESS"} class="flex items-center gap-2 px-2">
        <p class="text-gray-500">{@node.status}</p>
      </div>
    </div>
    """
  end

  @impl true
  def mount(:not_mounted_at_router, %{"node" => %Convoy.Node{} = node}, socket) do
    # whenever a shell is mounted for a particular node
    # we subscribe to that node, that's how we can stay
    # up to date on status changes and external messages
    # from other nodes.
    Convoy.NodePubsub.subscribe(node.name)

    {:ok,
     assign(socket,
       node: node,
       curr_command: "",
       history: []
     )}
  end

  @impl true
  def handle_event("check_cmd", %{"key" => key, "value" => value}, socket) do
    if key == "Enter" do
      node = socket.assigns.node
      Logger.info("this node: #{Node.self()}")
      Logger.info("name: #{node.name}")

      # TODO: if node.self corresponds to node.name than
      # we eval that command. otherwise we broadcast the cmd 
      # as a message to the proper node

      result =
        try do
          {val, _} = Code.eval_string(check_unsafe_cmd(value))
          inspect(val)
        rescue
          e -> "Error: #{Exception.message(e)}"
        end

      history = socket.assigns.history ++ [{value, result}]
      {:noreply, assign(socket, curr_command: "", history: history)}
    else
      {:noreply, assign(socket, curr_command: value)}
    end
  end

  @impl true
  def handle_event("del_node", _params, socket) do
    # starts a background task to handle deleting the node 
    # and communicating status updates -> faster UI updates
    %Convoy.Node{} = node = socket.assigns.node
    Task.start(fn -> Railway.delete_node(node) end)
    {:noreply, assign(socket, node: Convoy.Node.set_status(node, "deleting"))}
  end

  @impl true
  def handle_info({:load_instance_info, instance}, socket) do
    Logger.info(":load_instance_info: #{inspect(instance)}")
    node = Convoy.Node.load_instance_info(socket.assigns.node, instance)
    {:noreply, assign(socket, node: node)}
  end

  @impl true
  def handle_info({:set_status, status}, socket) do
    Logger.info(":set_status #{status}")
    node = socket.assigns.node

    if status != node.status do
      {:noreply, assign(socket, node: Convoy.Node.set_status(node, status))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(msg, socket) do
    # generic handle_info, so that we don't have 
    # to handle all possible messages for a channel
    Logger.info("skipping message: #{inspect(msg)}")
    {:noreply, socket}
  end

  # Some really basic unsafe command checking.
  # Still highly insecure. But could be worse!
  defp check_unsafe_cmd(cmd) when is_binary(cmd) do
    if String.contains?(cmd, @unsafe_terms) do
      raise "Command not permitted"
    else
      cmd
    end
  end
end
