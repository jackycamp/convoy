# Convoy

This project demonstrates how one might achieve elixir node clustering on Railway's infrastructure.
Both manually and automatically through node discovery and internal dns queries.

I've cooked up a basic UI that renders some elixir "shells". Consider them virtual shells
for the elixir nodes in our Railway environment and all on the same private internal network.

Below, we're manually connecting the nodes using `Node.connect/1`.

https://github.com/user-attachments/assets/458797d5-807a-46cb-b6c1-1de4309d1f97

[or check it out on yt](https://youtu.be/JZABhEIZkko)

And here, we spin up some new nodes, wait for them to deploy,
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

## Limitations and room for improvement

Some parts of the "terminal" behave pretty weird, not how you would expect
a normal terminal to operate, particularly line wrapping for longer commands,
retrieving the last nth command, etc.

Each shell literally gives "shell" access to the node allowing for
system commands potentially compromising the node. A little more work
could go into locking it down.

Realtime/collaborative/multi-client shells possible with a little more work. Right now, only
one client is supported at a time.

## Setting up the project

First, set some env vars:

```bash
export RAILWAY_API_URL=redacted
export RAILWAY_TOKEN=redacted
```

To start the app:

- Run `mix setup` to install and setup dependencies
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Cluster stuff

```bash
# add this to your /etc/hosts
127.0.0.1   convoy.local

# locally, with 3 separate shells open
# must specify port as to not interfere with eachother
PORT=4000 iex --name convoy1@convoy.local --cookie my_secret -S mix phx.server
PORT=4001 iex --name convoy2@convoy.local --cookie my_secret -S mix phx.server
PORT=4002 iex --name convoy3@convoy.local --cookie my_secret -S mix phx.server

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

In a deployed enviroment, ensure that some RELEASE environment variables are set.

RELEASE_DISTRIBUTION=name
RELEASE_NODE=convoy@convoy.railway.internal

## Docker

```bash
sudo docker build -t convoy:debug .
# build and spin it up locally
# note, you'll have to generate a secret key first
mix phx.gen.secret

sudo docker run \
-e SECRET_KEY_BASE="<redacted>" \
-e PHX_HOST=localhost \
-p4000:4000 \
convoy:debug
```
