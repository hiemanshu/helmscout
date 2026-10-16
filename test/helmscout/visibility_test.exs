defmodule Helmscout.VisibilityTest do
  use ExUnit.Case, async: true

  alias Helmscout.Visibility

  test "the opt-out topic is detected case-insensitively" do
    assert Visibility.hide_mcp_from_topics?(["helmscout-hide-mcp"])
    assert Visibility.hide_mcp_from_topics?(["kubesearch", "Helmscout-Hide-MCP"])
    refute Visibility.hide_mcp_from_topics?(["kubesearch"])
    refute Visibility.hide_mcp_from_topics?([])
    refute Visibility.hide_mcp_from_topics?(nil)
  end

  test "marker file name" do
    assert Visibility.marker_file() == ".helmscout-hide-mcp"
  end
end
