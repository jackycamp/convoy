defmodule ConvoyWeb.ConsoleLive do
  use ConvoyWeb, :live_view
  require Logger

  @unsafe_terms ["System", "File", "Port", "spawn", "Process", "cookie"]

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div
        class="bg-black w-full rounded-lg h-48 md:h-96 p-2 font-mono text-sm md:text-lg shadow-2xl overflow-y-auto"
        phx-click={JS.focus(to: "#cmd-#{length(@history)}-input")}
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
          <.console_input
            id={"cmd-#{length(@history)}-input"}
            value={@curr_command}
            onchange="check_cmd"
          />
        </div>
      </div>

      <div class="flex justify-end mt-12">
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
    {:ok,
     assign(socket,
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
  def handle_event("launch_node", _params, socket) do
    # res = Convoy.Railway.me()
    res = Convoy.Railway.get_services()
    Logger.info("query result: #{inspect(res)}")

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
