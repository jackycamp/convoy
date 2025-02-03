defmodule Convoy.DnsPollRailway do
  @moduledoc """
  A duped and slightly modified DNS polling strategy.
  Originally, DNSPoll was performing lookups that returned ip's
  but we want dns names as these are easier to know ahead of time 
  and given to you by Railway's internal private network for free.

  Simply, we use :inet_res.getbyname(query) instead of :inet_res.lookup(query).

  So instead of trying to connect nodes using: `<node_basename>@<ip-address>`
  we use `<node_basename>@<node_dns_name>`.

  For this specific project, we are looking for `convoy@convoy.railway.internal`.

  Checking out Cluster.Strategy.DNSPoll in the libcluster project
  is encouraged.

  ## Options

  * `poll_interval` - How often to poll in milliseconds (optional; default: 5_000)
  * `query` - DNS query to use (required; e.g. "my-app.example.com")
  * `node_basename` - The short name of the nodes you wish to connect to (required; e.g. "my-app")

  ## Usage

      config :libcluster,
        topologies: [
          my_topology_name: [
            strategy: #{__MODULE__},
            config: [
              polling_interval: 5_000,
              query: "my-app.example.com",
              node_basename: "my-app"]]]
  """

  use GenServer
  import Cluster.Logger

  alias Cluster.Strategy.State
  alias Cluster.Strategy

  @default_polling_interval 5_000

  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  @impl true
  def init([%State{meta: nil} = state]) do
    init([%State{state | :meta => MapSet.new()}])
  end

  def init([%State{} = state]) do
    {:ok, do_poll(state)}
  end

  @impl true
  def handle_info(:timeout, state), do: handle_info(:poll, state)
  def handle_info(:poll, state), do: {:noreply, do_poll(state)}
  def handle_info(_, state), do: {:noreply, state}

  defp do_poll(
         %State{
           topology: topology,
           connect: connect,
           disconnect: disconnect,
           list_nodes: list_nodes
         } = state
       ) do
    new_nodelist = state |> get_nodes() |> MapSet.new()
    removed = MapSet.difference(state.meta, new_nodelist)

    # Having trouble connecting your nodes? Or node discovery?
    # you may want to try hardcoding nodelist to see if you can
    # get it to force connect. e.g.
    # new_nodelist = MapSet.new([:"convoy@convoy.railway.internal"])

    new_nodelist =
      case Strategy.disconnect_nodes(
             topology,
             disconnect,
             list_nodes,
             MapSet.to_list(removed)
           ) do
        :ok ->
          new_nodelist

        {:error, bad_nodes} ->
          # Add back the nodes which should have been removed, but which couldn't be for some reason
          Enum.reduce(bad_nodes, new_nodelist, fn {n, _}, acc ->
            MapSet.put(acc, n)
          end)
      end

    new_nodelist =
      case Strategy.connect_nodes(
             topology,
             connect,
             list_nodes,
             MapSet.to_list(new_nodelist)
           ) do
        :ok ->
          new_nodelist

        {:error, bad_nodes} ->
          # Remove the nodes which should have been added, but couldn't be for some reason
          Enum.reduce(bad_nodes, new_nodelist, fn {n, _}, acc ->
            MapSet.delete(acc, n)
          end)
      end

    Process.send_after(self(), :poll, polling_interval(state))

    %{state | :meta => new_nodelist}
  end

  defp polling_interval(%{config: config}) do
    Keyword.get(config, :polling_interval, @default_polling_interval)
  end

  defp get_nodes(%State{config: config} = state) do
    query = Keyword.fetch(config, :query)
    node_basename = Keyword.fetch(config, :node_basename)

    resolver =
      Keyword.get(config, :resolver, fn query ->
        query
        |> String.to_charlist()
        |> lookup_all_names()
      end)

    resolve(query, node_basename, resolver, state)
  end

  defp resolve({:ok, query}, {:ok, node_basename}, resolver, _state)
       when is_binary(query) and is_binary(node_basename) and query != "" and node_basename != "" do
    me = node()

    query
    |> resolver.()
    |> Enum.reject(fn n -> is_nil(n) end)
    |> Enum.map(&format_node(&1, node_basename))
    |> Enum.reject(fn n -> n == me end)
  end

  defp resolve({:ok, invalid_query}, {:ok, invalid_basename}, _resolver, %State{topology: t}) do
    msg = "#{inspect(%{query: invalid_query, node_basename: invalid_basename})}"
    warn(t, "dns polling selected, but query or basename is invalid: #{msg}")
    []
  end

  defp resolve(:error, :error, _resolver, %State{topology: t}) do
    warn(t, "dns polling strategy is selected, but query and basename params missed")
    []
  end

  defp lookup_all_names(q) do
    case :inet_res.getbyname(q, :aaaa) do
      {:ok, {:hostent, name, _, _, _, _}} ->
        [name]

      {:error, reason} ->
        IO.warn("failed to get by name: #{inspect(reason)}")
        [nil]
    end
  end

  # This function is unused now
  def lookup_all_ips(q) do
    Enum.flat_map([:a, :aaaa], fn t -> :inet_res.lookup(q, :in, t) end)
  end

  # turn an ip into a node name atom, assuming that all other node names looks similar to our own name
  # defp format_node(ip, base_name), do: :"#{base_name}@#{:inet_parse.ntoa(ip)}"
  defp format_node(dns_name, base_name), do: :"#{base_name}@#{dns_name}"
end
