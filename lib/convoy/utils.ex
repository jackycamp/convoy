defmodule Convoy.Utils do
  require Logger

  @unsafe_terms [
    "System",
    "File",
    "Port",
    "spawn",
    "Process",
    "cookie",
    "env"
  ]

  # Some really basic unsafe command checking.
  # Still highly insecure. But could be worse!
  def check_unsafe_cmd(cmd) when is_binary(cmd) do
    if String.contains?(cmd, @unsafe_terms) do
      raise "Command not permitted"
    else
      cmd
    end
  end

  def run_remote_cmd(host, cmd) do
    Logger.info("attempting to run remote cmd: #{host}, #{cmd}")

    request =
      Finch.build(
        :post,
        host,
        [{"content-type", "application/json"}],
        Jason.encode!(%{value: cmd})
      )

    case Finch.request(request, Convoy.Finch) do
      {:ok, %Finch.Response{body: body, status: 200}} ->
        %{"result" => result} = Jason.decode!(body)
        result

      {:ok, %Finch.Response{status: status, body: body}} ->
        "Failed to run command on remote node: bad request #{status}: #{body}"

      {:error, reason} ->
        "Failed to run command on remote node: request failed #{inspect(reason)}"
    end
  end

  def run_local_cmd(cmd) do
    Logger.info("attempting to run local cmd: #{cmd}")

    try do
      {val, _} = Code.eval_string(check_unsafe_cmd(cmd))
      inspect(val)
    rescue
      e -> "Error: #{Exception.message(e)}"
    end
  end
end
