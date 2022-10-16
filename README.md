# Libcluster Hop Strategy
Easily setup distributed Elixir on [Hop](https://hop.io)!

This package so far contains one strategy, `ClusterHop.Strategy.Deployment`, which uses the Hop
API to find all containers running under one deployment.\
It will then attempt to register each container via the container internal IPs to each node.

## Installation

### 0. Add Libcluster Hop as a dependency
Currently, this isn't available on Hex.pm, but in the meantime you can get it straight from GitHub like so:
```elixir
defp deps do
    [
      # ... your other deps
      {:libcluster, "~> 3.3"},
      {:libcluster_hop,
       github: "hiett/libcluster_hop", ref: "6d9e519c4eb22c58c6f171dc9a739331a2a1194c"} # (this is current stable ref)
    ]
end
```

### 1. Create a Hop Project Token
Create a project token with manage deployments permissions.

This token is used to get all the containers in a deployment from the Hop API.

### 2. Create / Get a Deployment ID
This will start with deployment_


### 3. Setup the strategy in your Application file

Here's an example of what a barebones Application file would look like:
```elixir
defmodule HopTestapp do
  use Application

  def start(_type, _args) do
    IO.puts("Starting test app")

    topologies = [
      hop: [
        strategy: ClusterHop.Strategy.Deployment,
        config: [
          deployment_id: "deployment_xxx",
          hop_token: "ptk_xxx",
          app_prefix: "my_amazing_app"
        ]
      ]
    ]

    children = [
      {Cluster.Supervisor, [topologies, [name: HopTestapp.ClusterSupervisor]]}
    ]

    opts = [strategy: :one_for_one, name: HopTestapp.Supervisor]

    Supervisor.start_link(children, opts)
  end
end

```
Fill in the `deployment_id`, `hop_token` and `app_prefix`.
Libcluster Hop will automatically find the internal container IP (starts with 10.1.x.x), and form a nodename in the
following format: `app_prefix@internal_ip`

### 4. [Important!] Set the following Environment Variable in your Hop deployment:
`RELEASE_DISTRIBUTION=none`

You need to set this because Elixir will automatically attempt to start the application in distributed mode upon
creation of a release. However, this will have the incorrect nodename, because internal IPs aren't instantly available
to containers on Hop.

Libcluster Hop will start the node itself when it has obtained the IP and formed a nodename.

### 5. Scale away!
You're all good to go. All containers inside a deployment will now be linked together.