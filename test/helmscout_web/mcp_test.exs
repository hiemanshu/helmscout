defmodule HelmscoutWeb.MCPTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias HelmscoutWeb.MCP

  defp call(payload) do
    conn(:post, "/mcp")
    |> Map.put(:body_params, payload)
    |> MCP.call(MCP.init([]))
  end

  defp decoded(conn), do: Jason.decode!(conn.resp_body)

  test "initialize advertises tool capability" do
    conn = call(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})
    assert conn.status == 200
    body = decoded(conn)
    assert body["id"] == 1
    assert body["result"]["serverInfo"]["name"] == "helmscout"
    assert Map.has_key?(body["result"]["capabilities"], "tools")
  end

  test "tools/list returns descriptors with schemas" do
    conn = call(%{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"})
    body = decoded(conn)
    names = Enum.map(body["result"]["tools"], & &1["name"])

    assert "search_helm_releases" in names
    assert "get_release_values" in names

    tool = Enum.find(body["result"]["tools"], &(&1["name"] == "search_helm_releases"))
    assert tool["inputSchema"]["type"] == "object"
  end

  test "notifications get an empty 202 response" do
    conn = call(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"})
    assert conn.status == 202
    assert conn.resp_body == ""
  end

  test "unknown methods return a json-rpc error" do
    conn = call(%{"jsonrpc" => "2.0", "id" => 9, "method" => "does/not/exist"})
    body = decoded(conn)
    assert body["error"]["code"] == -32_601
  end

  test "GET is rejected" do
    conn = MCP.call(conn(:get, "/mcp"), [])
    assert conn.status == 405
  end
end
