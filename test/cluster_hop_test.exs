defmodule ClusterHopTest do
  use ExUnit.Case

  test "checks can read from hop api" do
    resp = ClusterHop.get_containers_in_deployment("deployment", "token")
    IO.inspect(resp)

    assert resp != {:error}
  end

  test "ip to nodename conversion" do
    resp = ClusterHop.Strategy.Deployment.ip_to_nodename(["192.168.1.233"], "test-app")

    assert resp == [:"test-app@192.168.1.233"]
  end
end
