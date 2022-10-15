defmodule ClusterHop do
  use Tesla

  plug(Tesla.Middleware.BaseUrl, "https://api.hop.io/v1")
  plug(Tesla.Middleware.JSON)

  def get_containers_in_deployment(deployment_id, token) when is_binary(deployment_id) do
    case get("/ignite/deployments/" <> deployment_id <> "/containers", headers: [{"authorization", token}]) do
      {:ok, %{status: 200, body: body}} -> {:ok, extract_containers_from_response(body)}
      _ -> {:error}
    end
  end

  defp extract_containers_from_response(%{"data" => %{"containers" => containers}})
       when is_list(containers) do
    containers
    |> Stream.filter(&(Map.get(&1, "state", "unknown") == "running"))
    |> Enum.map(&%{id: Map.get(&1, "id"), internal_ip: Map.get(&1, "internal_ip")})
  end

  defp extract_containers_from_response(_), do: {:error}
end
