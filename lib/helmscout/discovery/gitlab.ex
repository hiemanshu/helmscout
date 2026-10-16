defmodule Helmscout.Discovery.Gitlab do
  @moduledoc "GitLab topic discovery (gitlab.com public projects)."

  require Logger

  alias Helmscout.Http

  @per_page 100

  @spec topics([String.t()], keyword()) :: [map()]
  def topics(topics, opts \\ []) do
    max_pages = Keyword.get(opts, :max_pages) || 10
    concurrency = Keyword.get(opts, :concurrency) || 8

    topics
    |> Task.async_stream(
      fn topic ->
        repos = search_topic(topic, 1, max_pages)
        Logger.info("      gitlab topic #{topic}: #{length(repos)} repos")
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

  defp search_topic(_topic, page, max_pages) when page > max_pages, do: []

  defp search_topic(topic, page, max_pages) do
    params = [
      topic: topic,
      order_by: "last_activity_at",
      sort: "desc",
      per_page: @per_page,
      page: page
    ]

    case Http.get("https://gitlab.com/api/v4/projects", params: params) do
      {:ok, projects} when is_list(projects) ->
        repos = Enum.map(projects, &from_project(&1, topic))

        if length(projects) < @per_page do
          repos
        else
          repos ++ search_topic(topic, page + 1, max_pages)
        end

      {:ok, _} ->
        []

      {:error, reason} ->
        Logger.warning("gitlab topic search #{topic} failed: #{inspect(reason)}")
        []
    end
  end

  defp from_project(p, topic) do
    %{
      name: p["path_with_namespace"],
      url: p["web_url"],
      forge: "gitlab",
      branch: p["default_branch"] || "main",
      stars: p["star_count"] || 0,
      pushed_at: Helmscout.Discovery.Github.parse_time(p["last_activity_at"]),
      topics: p["topics"] || [topic],
      discoverer: "gitlab_topic:#{topic}"
    }
  end
end
