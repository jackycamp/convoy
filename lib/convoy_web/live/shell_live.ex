defmodule ConvoyWeb.ShellLive do
  use ConvoyWeb, :live_view
  alias Phoenix.LiveView.JS
  alias Convoy.Railway
  require Logger

  @unsafe_terms ["System", "File", "Port", "spawn", "Process", "cookie", "env"]

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="relative text-white bg-black w-full rounded-lg min-w-[30vw] max-w-[30vw] h-48 md:h-96 font-mono text-sm xl:text-lg shadow-2xl overflow-y-auto"
      phx-click={JS.focus(to: "#node-shell-#{@node_id}-cmd-#{length(@history)}-input")}
    >
      <div class="flex justify-between text-sm bg-[#343639] py-2 px-2 mb-2">
        <div>{@node["serviceName"]}</div>
        <div :if={!@is_ctrl} phx-click="del_node" class="hover:text-gray-500 cursor-pointer">
          <.icon name="hero-power" class="h-5" />
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

      <div class="flex items-center gap-2 px-2">
        <p class="text-white">iex({length(@history)})></p>
        <.shell_input
          id={"node-shell-#{@node_id}-cmd-#{length(@history)}-input"}
          value={@curr_command}
          onchange="check_cmd"
        />
      </div>
    </div>
    """
  end

  @impl true
  def mount(
        :not_mounted_at_router,
        %{"node_id" => node_id, "is_ctrl" => is_ctrl, "node" => node},
        socket
      ) do
    # TODO: render name of node at bottom of shell, or perhaps top of shell? with status?
    # should have some tools available, such as power, etc
    #
    # whenever a node is launched, subscribe to that node

    {:ok,
     assign(socket,
       node_id: node_id,
       node: node,
       is_ctrl: is_ctrl,
       curr_command: "",
       history: []
     )}
  end

  @impl true
  def handle_event("check_cmd", %{"key" => key, "value" => value}, socket) do
    if key == "Enter" do
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
    id = socket.assigns.node_id
    service_id = socket.assigns.node["serviceId"]
    Logger.info("del node id: #{id}, service id #{service_id}")

    case Railway.delete_service(service_id) do
      {:ok, %Neuron.Response{status_code: 200, body: body}} ->
        Phoenix.PubSub.broadcast(Convoy.PubSub, "nodes", {:del_node, id})
        Logger.info("deleted node: #{inspect(body)}")

      {:error, reason} ->
        Logger.info("could not delete node: #{inspect(reason)}")
    end

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
