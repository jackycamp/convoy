defmodule ConvoyWeb.ConsoleLive do
  use ConvoyWeb, :live_view
  require Logger

  @unsafe_terms ["System", "File", "Port", "spawn", "Process"]

  def render(assigns) do
    ~H"""
    <div>
      <div
        class="bg-black w-full rounded-lg h-96 p-2 font-mono text-lg shadow-2xl overflow-y-auto"
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
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       curr_command: "",
       history: []
     )}
  end

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

  @doc """
  Some really, really, basic unsafe command checking.
  Still highly insecure. But could be worse!
  """
  def check_unsafe_cmd(cmd) when is_binary(cmd) do
    if String.contains?(cmd, @unsafe_terms) do
      raise "Command not permitted"
    else
      cmd
    end
  end
end
