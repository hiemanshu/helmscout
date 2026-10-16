defmodule Helmscout.Visibility do
  @moduledoc """
  Owner opt-out.

  A repository can ask not to be exposed to AI agents with the
  **`helmscout-hide-mcp`** topic, or a **`.helmscout-hide-mcp`** marker file in its
  root. It still appears on the website and the JSON API; it is simply omitted
  from the MCP server's results.

  To leave helmscout entirely, make the repository private — only public
  repositories are indexed.
  """

  import Ecto.Query

  alias Helmscout.{Repo, Source}

  @marker ".helmscout-hide-mcp"
  @topic "helmscout-hide-mcp"

  @doc "Marker file checked in a cloned repository's root."
  def marker_file, do: @marker

  @doc "GitHub topic that opts a repository out of MCP."
  def topic, do: @topic

  @doc "True when the given topics include the opt-out topic."
  def hide_mcp_from_topics?(topics) do
    topics
    |> List.wrap()
    |> Enum.map(&String.downcase(to_string(&1)))
    |> Enum.member?(@topic)
  end

  @doc """
  Source ids excluded for a scope. Only the MCP scope excludes anything; the
  website/API (`:api`) shows everything.
  """
  def excluded_ids(:mcp), do: hidden_mcp_ids()
  def excluded_ids(_api), do: []

  @doc "Source ids that opted out of MCP."
  def hidden_mcp_ids do
    Repo.all(from s in Source, where: s.hide_mcp, select: s.id)
  end
end
