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
      class="relative bg-black w-full rounded-lg min-w-[30vw] max-w-[30vw] h-48 md:h-96 p-2 font-mono text-sm md:text-lg shadow-2xl overflow-y-auto"
      phx-click={JS.focus(to: "#node-shell-#{@node_id}-cmd-#{length(@history)}-input")}
    >
      <%= for {{cmd, res}, index} <- Enum.with_index(@history) do %>
        <div>
          <div class="flex items-center gap-2">
            <p class="text-white">iex({index})></p>
            <p class="text-white">{cmd}</p>
          </div>
          <p class={if String.contains?(res, "Error"), do: "text-red-500", else: "text-white"}>
            {res}
          </p>
        </div>
      <% end %>

      <div class="flex items-center gap-2">
        <p class="text-white">iex({length(@history)})></p>
        <.shell_input
          id={"node-shell-#{@node_id}-cmd-#{length(@history)}-input"}
          value={@curr_command}
          onchange="check_cmd"
        />
      </div>

      <div class="absolute bottom-0 right-0 text-white">
        <div><.icon name="hero-power" /></div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(:not_mounted_at_router, %{"node_id" => node_id, "is_ctrl" => is_ctrl}, socket) do
    # TODO: render name of node at bottom of shell, or perhaps top of shell? with status?
    # should have some tools available, such as power, etc
    #
    # whenever a node is launched, subscribe to that node

    {:ok,
     assign(socket,
       node_id: node_id,
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
