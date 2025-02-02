defmodule Convoy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Cluster.Supervisor,
       [Application.get_env(:libcluster, :topologies), [name: Convoy.ClusterSupervisor]]},
      ConvoyWeb.Telemetry,
      {Phoenix.PubSub, name: Convoy.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch,
       name: Convoy.Finch,
       pools: %{
         default: [
           conn_opts: [
             transport_opts: [inet6: true]
           ]
         ]
       }},
      # Start a worker by calling: Convoy.Worker.start_link(arg)
      # {Convoy.Worker, arg},
      # Start to serve requests, typically the last entry
      Convoy.ConvoyWorker,
      ConvoyWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Convoy.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ConvoyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
