defmodule ClusterHopTest do
  use ExUnit.Case

  test "checks can read from hop api" do
    resp = ClusterHop.get_containers_in_deployment("deployment", "token")
    IO.inspect(resp)

    assert resp != {:error}
  end
end
