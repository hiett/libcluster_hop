defmodule ClusterHop.Strategy.Deployment do
  use GenServer

  alias Cluster.Strategy.State

  @default_polling_interval 5_000

  def start_link(opts) do
    Application.ensure_all_started(:tesla)
    GenServer.start_link(__MODULE__, opts)
  end

  # libcluster ~> 3.0
  @impl GenServer
  def init([%State{} = state]) do
    state = state |> Map.put(:meta, MapSet.new())

    {:ok, load(state)}
  end

  # libcluster ~> 2.0
  def init(opts) do
    state = %State{
      topology: Keyword.fetch!(opts, :topology),
      connect: Keyword.fetch!(opts, :connect),
      disconnect: Keyword.fetch!(opts, :disconnect),
      list_nodes: Keyword.fetch!(opts, :list_nodes),
      config: Keyword.fetch!(opts, :config),
      meta: MapSet.new([])
    }

    {:ok, load(state)}
  end

  defp load(
         %State{
           topology: topology,
           connect: connect,
           disconnect: disconnect,
           list_nodes: list_nodes
         } = state
       ) do
    case get_nodes(state) do
      {:ok, new_nodelist} ->
        removed = MapSet.difference(state.meta, new_nodelist)

        new_nodelist =
          case Cluster.Strategy.disconnect_nodes(
                 topology,
                 disconnect,
                 list_nodes,
                 MapSet.to_list(removed)
               ) do
            :ok ->
              new_nodelist

            {:error, bad_nodes} ->
              Enum.reduce(bad_nodes, new_nodelist, fn {n, _}, acc ->
                MapSet.put(acc, n)
              end)
          end

        new_nodelist =
          case Cluster.Strategy.connect_nodes(
                 topology,
                 connect,
                 list_nodes,
                 MapSet.to_list(new_nodelist)
               ) do
            :ok ->
              new_nodelist

            {:error, bad_nodes} ->
              Enum.reduce(bad_nodes, new_nodelist, fn {n, _}, acc ->
                MapSet.delete(acc, n)
              end)
          end

        Process.send_after(
          self(),
          :load,
          Keyword.get(state.config, :polling_interval, @default_polling_interval)
        )

        %{state | :meta => new_nodelist}

      _ ->
        Process.send_after(
          self(),
          :load,
          Keyword.get(state.config, :polling_interval, @default_polling_interval)
        )

        state
    end
  end

  defp get_nodes(%State{config: config}) do
    app_prefix = Keyword.get(config, :app_prefix, "app")
    deployment_id = Keyword.fetch!(config, :deployment_id)
    hop_token = Keyword.fetch!(config, :hop_token)

    case ClusterHop.get_containers_in_deployment(deployment_id, hop_token) do
      {:ok, containers} ->
        ips = containers |> Enum.map(&Map.get(&1, :ip)) |> ip_to_nodename(app_prefix)
        {:ok, MapSet.new(ips)}

      {:error} ->
        {:error, []}
    end
  end

  defp ip_to_nodename(list, app_prefix) when is_list(list) do
    list
    |> Enum.map(&:"#{app_prefix}@#{&1}")
  end
end
