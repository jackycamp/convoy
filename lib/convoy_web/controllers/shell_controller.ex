defmodule ConvoyWeb.ShellController do
  use ConvoyWeb, :controller
  alias Convoy.Utils

  def cmd(conn, params) do
    case run_cmd(params) do
      {:ok, res} ->
        conn
        |> put_status(:ok)
        |> json(%{result: res})
    end
  end

  defp run_cmd(%{"value" => value}) do
    result =
      try do
        {val, _} = Code.eval_string(Utils.check_unsafe_cmd(value))
        inspect(val)
      rescue
        e -> "Error: #{Exception.message(e)}"
      end

    {:ok, result}
  end
end
