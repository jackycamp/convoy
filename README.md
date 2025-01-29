# Convoy

To start your Phoenix server:

- Run `mix setup` to install and setup dependencies
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Cluster stuff

```bash
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

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix
