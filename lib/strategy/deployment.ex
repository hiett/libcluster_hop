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

    setup_local_nodename(state)

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

    setup_local_nodename(state)

    {:ok, load(state)}
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    handle_info(:load, state)
  end

  def handle_info(:load, %State{} = state) do
    {:noreply, load(state)}
  end

  def handle_info(_, state) do
    {:noreply, state}
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
        IO.puts("Got nodes:")
        IO.inspect(new_nodelist)

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
    env_var_deployment_id = System.get_env("DEPLOYMENT_ID")
    deployment_id = Keyword.get(config, :deployment_id, env_var_deployment_id)
    hop_token = Keyword.fetch!(config, :hop_token)

    case ClusterHop.get_containers_in_deployment(deployment_id, hop_token) do
      {:ok, containers} ->
        ips = containers |> Enum.map(&Map.get(&1, :internal_ip)) |> ip_to_nodename(app_prefix)
        {:ok, MapSet.new(ips)}

      {:error} ->
        {:error, []}
    end
  end

  def ip_to_nodename(list, app_prefix) when is_list(list) do
    list |> Enum.map(&make_nodename(&1, app_prefix))
  end

  defp make_nodename(ip, app_prefix), do: :"#{app_prefix}@#{ip}"

  defp get_local_node_ip() do
    IO.inspect(:inet.getif())
    IO.inspect(:inet.getifaddrs())

    case :inet.getif() do
      {:ok, []} ->
        # no ips found
        # wait and recall
        IO.puts("Waiting one second then trying again - couldn't find an IP")
        :timer.sleep(1000)
        get_local_node_ip()

      {:ok, ips} ->
        case check_found_ip(ips) do
          {:ok, ip} ->
            string_ip =
              Tuple.to_list(ip)
              |> Enum.join(".")

            IO.puts("Using IP #{string_ip}")

            string_ip

          _ ->
            # something went wrong
            IO.puts("Waiting one second then trying again - couldn't find an IP")
            :timer.sleep(1000)
            get_local_node_ip()
        end

      _ ->
        # something went wrong
        IO.puts("Waiting one second then trying again - couldn't find an IP")
        :timer.sleep(1000)
        get_local_node_ip()
    end
  end

  defp check_found_ip([{{10, 1, a, b}, _, _} | rest]), do: {:ok, {10, 1, a, b}}

  defp check_found_ip([head | rest]), do: check_found_ip(rest)

  defp check_found_ip([]), do: {:error, :not_found}

  defp setup_local_nodename(%State{config: config}) do
    # First we need to enable epmd
    _ = :os.cmd("epmd -daemon") # Start up epmd manually

    # Wait a sec to ensure its started
    :timer.sleep(1000)

    app_prefix = Keyword.get(config, :app_prefix, "app")
    ip = get_local_node_ip()
    nodename = make_nodename(ip, app_prefix)

    {:ok, _pid} = Node.start(nodename)
  end
end
