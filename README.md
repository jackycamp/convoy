# Convoy

This repo demonstrates how one can achieve elixir node clustering on Railway's infrastructure
both manually and automatically through node discovery and internal dns queries.

I've cooked up a basic UI that renders some elixir "shells". Consider them virtual shells
for the elixir nodes in our Railway environment and all on the same private internal network.

In the clip below, we're manually connecting the nodes using `Node.connect/1`.

https://github.com/user-attachments/assets/458797d5-807a-46cb-b6c1-1de4309d1f97

[or check it out on yt](https://youtu.be/JZABhEIZkko)

And in this clip, we spin up some new nodes, wait for them to deploy,
and see them connect automatically!!

https://github.com/user-attachments/assets/ab1a363f-d636-4fc2-b706-11c24f6ff363

[also on yt](https://youtu.be/JZABhEIZkko)

## Modules of interest

**ConvoyWeb.ConsoleLive**

`lib/convoy_web/live/console_live.ex`

The Phoenix LiveView that is the entry point of the app. Allows one
to spin up and spin down elixir nodes, and interact with their shells, in a railway environment.

**ConvoyWeb.ShellLive**

`lib/convoy_web/live/shell_live.ex`

The Phoenix LiveView that emulates a "shell" for the corresponding
elixir node. The commands you run in the shell execute on the
node itself. All stdout/stderr messages you see are directly from
that node.

**Convoy.Railway**

`lib/convoy/live/railway.ex`

The module that interacts with the Railway environment.
Performs the graphql queries and mutations to manage
nodes and services in the environment.

**Convoy.DnsPollRailway**

`lib/dns_poll_railway.ex`

The custom, Railway specific, clustering/node discovery
strategy. Allows for auto-discovery and joining of elixir nodes
to the cluster. Literally duped from libcluster's `DNSPoll` strategy
and modified for more debug logging and resolving to dns names not
ip's.

## Setting up the project

Assumes you have elixir and erlang installed. If you don't you can
follow the [Phoenix installation instructions](https://hexdocs.pm/phoenix/installation.html), they explain how to get elixir/erlang setup.

These env vars are required to start the project locally:

```bash
export RAILWAY_API_URL=redacted
export RAILWAY_TOKEN=redacted
```

To start the app:

```bash
mix deps.get # or you could do mix setup
mix phx.server
```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Cluster stuff

### Elixir Cluster on Railway

There are a few extra steps needed to make sure that your elixir nodes can connect
using the erlang port mapper daemon (EPMD) on Railway's private network.

For each node, we need to set some env vars:

```bash
# standard for phoenix deployments
PHX_HOST=..
SECRET_KEY_BASE=..

# required for clustering via node names and dns lookups
# the RELEASE_NODE should correspond to the node's
# internal dns name that railway generates
RELEASE_DISTRIBUTION=name
RELEASE_NODE=convoy@convoy.railway.internal
# cookies must match between nodes
RELEASE_COOKIE="some-super-secret-cookie"
# critical erlang flags
ERL_AFLAGS="-proto_dist inet6_tcp -kernel inet_dist_listen_min 4444 inet_dist_listen_max 4444"
```

A little bit more about the erlang flags:

`-proto_dist inet6_tcp` forces erlang's distribution protocol to use ipv6. Railway's
internal private network only supports ipv6.

`-kernel inet_dist_listen_min 4444 inet_dist_listen_max 4444` ensures that inter-node distributed communication happens on a specific port. If not set a random high numbered port will be used which is not supported by railway's internal network. You must be explicit about the port.

If only these environment variables are set, nodes should be able to communicate. But you will have to manually connect them using `Node.connect/1` e.g. `Node.connect(:"convoy@convoy.railway.internal")`.

### Elixir Node Auto-Discovery on Railway\*\*

It'd be cooler if the nodes automatically connect when you spin them up. Utilizing `libcluster` and our own custom dns strategy they can!

Put this `libcluster` config in your `config.exs`:

```elixir
config :libcluster,
  topologies: [
    convoy_topology: [
      strategy: Convoy.DnsPollRailway,
      config: [
        polling_interval: 5_000,
        query: "convoy.railway.internal",
        node_basename: "convoy"
      ]
    ]
  ]
```

`Convoy.DnsPollRailway` is our own custom strategy defined in `lib/dns_poll_railway.ex`.
It's a literal dupe of `libcluster`'s `Cluster.Strategy.DNSPoll` but instead of looking up ip's with `:inet_res.lookup/2`, we lookup hostnames with `:inet_res.getbyname/2` based off of the query provided in the config. In our case, the query corresponds to the "control-plane" of the cluster.

Now, when you spin up nodes, you can just do `Node.list` on any node in the cluster to see them connect.

> Please keep in mind that `Convoy.DnsPollRailway` is not production ready as thorough testing has yet to be done. But it can be a good starting point and can be adjusted based on your needs.

### Local Cluster

If you want to setup your local instance for manual clustering purposes you should:

```bash
# add this to your /etc/hosts
127.0.0.1   convoy.local

# start a node, specifying port, name, and cookie
PORT=4000 iex --name convoy@convoy.local --cookie my_secret -S mix phx.server
# for other local nodes you would do:
PORT=4002 iex --name convoy2@convoy.local --cookie my_secret -S mix phx.server
PORT=4003 iex --name convoy3@convoy.local --cookie my_secret -S mix phx.server

# but the nodes won't automatically be connected
iex> Node.list
[]

# to connect nodes you can do:
iex> Node.connect(:"convoy2@convoy.local")
iex> Node.connect(:"convoy3@convoy.local")
iex> Node.list
[:"convoy3@convoy.local", :"convoy2@convoy.local"]

# can also communicate with the ConvoyWorker GenServer running on each node
iex(convoy3@convoy.local)5> send({Convoy.ConvoyWorker, :"convoy1@convoy.local"}, :ping)

# then on convoy1 you should see
Received ping on node convoy1@convoy.local
```

## Limitations and room for improvement

Some parts of the "terminal" behave pretty weird, not how you would expect
a normal terminal to operate, particularly line wrapping for longer commands,
retrieving the last nth command, etc.

Each shell literally gives "shell" access to the node allowing for
system commands potentially compromising the node. A little more work
could go into locking it down.

Realtime/collaborative/multi-client shells possible with a little more work. Right now, only
one client is supported at a time.

## Docker

```bash
# build and spin it up locally
# note, you'll have to generate a secret key first
sudo docker build -t convoy:debug .
mix phx.gen.secret

sudo docker run \
-e SECRET_KEY_BASE="<redacted>" \
-e PHX_HOST=localhost \
-e RELEASE_DISTRIBUTION=name \
-e RELEASE_NODE=convoy@convoy.local \
-e PORT=4000 \
-p4000:4000 \
convoy:debug
```
