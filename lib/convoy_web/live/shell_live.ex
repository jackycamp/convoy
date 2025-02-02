defmodule ConvoyWeb.ShellLive do
  use ConvoyWeb, :live_view
  alias Phoenix.LiveView.JS
  alias Convoy.Railway
  alias Convoy.Utils
  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="text-white bg-black rounded-lg w-[80vw] sm:w-[36rem] font-mono text-sm xl:text-lg shadow-2xl"
      phx-click={JS.focus(to: "#node-shell-#{@node.name}-cmd-#{length(@history)}-input")}
    >
      <!-- static top shell bar (showing name and actions) -->
      <div class="flex justify-between text-sm bg-[#343639] py-2 px-2 mb-2 rounded-t-lg">
        <div class="flex gap-1 items-center">
          <p class={if @is_remote?, do: "text-white", else: "text-cornflowerblue"}>{@node.name}</p>
          <p :if={@is_remote?} class="text-xs text-gray-500">(remote)</p>
        </div>
        <div
          :if={!@node.control_plane? && @node.status == "SUCCESS"}
          phx-click="del_node"
          class="hover:text-gray-500 cursor-pointer"
        >
          <.icon name="hero-power" class="h-5" />
        </div>
        <div :if={@node.status == "deleting"}>
          <.icon name="hero-arrow-path" class="h-5 animate-spin" />
        </div>
      </div>
      
    <!-- main shell content, scrolls vertically -->
      <div class="h-72 sm:h-96 overflow-y-auto">
        <!-- history of commands -->
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
        
    <!-- current shell input -->
        <div
          :if={@node.status == "SUCCESS"}
          phx-hook="UseFocus"
          id={"node-shell-#{@node.name}-cmd-container"}
          class="flex items-center gap-2 px-2"
        >
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
       history: [],
       is_remote?: is_remote_node(node.name)
     )}
  end

  @impl true
  def handle_event("check_cmd", %{"key" => key, "value" => value}, socket) do
    case key do
      "Enter" ->
        socket = run_cmd(socket, value)
        %{node: node, history: history} = socket.assigns
        selector = "node-shell-#{node.name}-cmd-#{length(history)}-input"
        {:noreply, push_event(socket, "focus", %{selector: selector})}

      "ArrowUp" ->
        socket = load_last_cmd(socket)
        %{node: node, history: history, curr_command: curr_command} = socket.assigns
        selector = "node-shell-#{node.name}-cmd-#{length(history)}-input"
        {:noreply, push_event(socket, "set_value", %{selector: selector, value: curr_command})}

      _ ->
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

  defp run_cmd(socket, value) do
    node = socket.assigns.node

    result =
      if is_remote_node(node.name) do
        internal_dns = "https://#{node.name}.railway.internal:4000/api/cmd"
        Utils.run_remote_cmd(internal_dns, value)
      else
        Utils.run_local_cmd(value)
      end

    history = socket.assigns.history ++ [{value, result}]
    assign(socket, curr_command: "", history: history)
  end

  defp load_last_cmd(socket) do
    %{history: history} = socket.assigns

    case List.last(history) do
      {last_cmd, _} ->
        IO.puts("got last command: #{last_cmd}")
        assign(socket, curr_command: last_cmd)

      nil ->
        assign(socket, curr_command: "")
    end
  end

  defp is_remote_node(node_name) do
    self = "#{Node.self()}"
    node_with_railway = "#{node_name}@#{node_name}.railway.internal"
    node_with_local = "#{node_name}@#{node_name}.local"

    self != node_with_railway && self != node_with_local
  end
end
