# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :convoy,
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :convoy, ConvoyWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ConvoyWeb.ErrorHTML, json: ConvoyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Convoy.PubSub,
  live_view: [signing_salt: "4TdfSZgN"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :convoy, Convoy.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  convoy: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  convoy: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

query =
  case Mix.env() do
    :dev -> "convoy.local"
    :prod -> "convoy.railway.internal"
    _ -> "convoy.local"
  end

IO.puts("libcluster query: #{query}")

config :libcluster,
  topologies: [
    convoy_topology: [
      # ref: https://hexdocs.pm/libcluster/Cluster.Strategy.DNSPoll.html#content
      # strategy: Cluster.Strategy.DNSPoll,
      strategy: Convoy.DnsPollRailway,
      config: [
        polling_interval: 5_000,
        query: query,
        node_basename: "convoy"
      ]
    ]
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
