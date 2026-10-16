defmodule Helmscout.Discovery.Gitea do
  @moduledoc """
  Gitea/Forgejo/Codeberg discovery via the Gitea-compatible REST API.

  Forges are configurable with `HELMSCOUT_GITEA_FORGES` (comma-separated base
  URLs); defaults to Codeberg.
  """

  require Logger

  alias Helmscout.Http

  @limit 50

  @spec topics([String.t()], keyword()) :: [map()]
  def topics(topics, opts \\ []) do
    forges = forges(Keyword.get(opts, :forges))
    max_pages = Keyword.get(opts, :max_pages) || 8
    concurrency = Keyword.get(opts, :concurrency) || 8

    for forge <- forges, topic <- topics do
      {forge, topic}
    end
    |> Task.async_stream(
      fn {forge, topic} ->
        repos = search(forge, topic, 1, max_pages)
        Logger.info("      gitea #{forge} #{topic}: #{length(repos)} repos")
        repos
      end,
      max_concurrency: concurrency,
      timeout: 120_000,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, repos} -> repos
      _ -> []
    end)
  end

  defp search(_forge, _topic, page, max_pages) when page > max_pages, do: []

  defp search(forge, topic, page, max_pages) do
    params = [q: topic, topic: true, limit: @limit, page: page]

    case Http.get("#{forge}/api/v1/repos/search", params: params) do
      {:ok, %{"data" => repos}} when is_list(repos) ->
        candidates =
          repos
          |> Enum.filter(&topic_match?(&1, topic))
          |> Enum.map(&from_repo(&1, forge, topic))

        if length(repos) < @limit do
          candidates
        else
          candidates ++ search(forge, topic, page + 1, max_pages)
        end

      {:ok, _} ->
        []

      {:error, reason} ->
        Logger.warning("gitea topic search #{forge} #{topic} failed: #{inspect(reason)}")
        []
    end
  end

  defp topic_match?(repo, topic) do
    topics = repo["topics"] || []
    topics == [] or topic in topics
  end

  defp from_repo(repo, forge, topic) do
    %{
      name: repo["full_name"],
      url: repo["html_url"] || "#{forge}/#{repo["full_name"]}",
      forge: forge_forge(forge),
      branch: repo["default_branch"] || "main",
      stars: repo["stars_count"] || 0,
      pushed_at: Helmscout.Discovery.Github.parse_time(repo["updated_at"]),
      topics: repo["topics"] || [topic],
      discoverer: "gitea_topic:#{topic}"
    }
  end

  defp forge_forge(url) do
    cond do
      String.contains?(url, "codeberg.org") -> "codeberg"
      String.contains?(url, "forgejo") -> "forgejo"
      true -> "gitea"
    end
  end

  defp forges(nil) do
    case System.get_env("HELMSCOUT_GITEA_FORGES") do
      nil -> ["https://codeberg.org"]
      "" -> ["https://codeberg.org"]
      value -> value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    end
  end

  defp forges(list) when is_list(list), do: list
end
