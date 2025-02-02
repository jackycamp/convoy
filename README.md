# Convoy

This project demonstrates how one might achieve elixir node clustering on Railway's infrastructure.
Both manually and automatically through node discovery and internal dns queries.

I've cooked up a basic UI that renders some elixir "shells". Consider them virtual shells
for the elixir nodes in our Railway environment and all on the same private internal network.

Below, we're manually connecting the nodes using `Node.connect/1`.


https://github.com/user-attachments/assets/458797d5-807a-46cb-b6c1-1de4309d1f97


[Manually connecting elixir nodes](https://youtu.be/JZABhEIZkko)

And here, we spin up some new nodes, wait for them to deploy,
and see them connect automatically!!

[Elixir nodes connected auto-discover](https://youtu.be/JZABhEIZkko)

## Setting up the project

First, set some env vars:

```bash
export RAILWAY_API_URL=redacted
export RAILWAY_TOKEN=redacted
```

To start your Phoenix server:

- Run `mix setup` to install and setup dependencies
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

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
# build and spin it up locally
# note, you'll have to generate a secret key first
mix phx.gen.secret

sudo docker run \
-e SECRET_KEY_BASE="<redacted>" \
-e PHX_HOST=localhost \
-p4000:4000 \
convoy:debug
```

For more information about deploying with Docker see
https://hexdocs.pm/phoenix/releases.html#containers

Here are some useful release commands you can run in any release environment:

    # To build a release
    mix release

    # To start your system with the Phoenix server running
    _build/dev/rel/convoy/bin/server

Once the release is running you can connect to it remotely:

    _build/dev/rel/convoy/bin/convoy remote

To list all commands:

    _build/dev/rel/convoy/bin/convoy

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix
