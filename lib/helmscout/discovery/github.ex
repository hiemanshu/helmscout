defmodule Helmscout.Discovery.Github do
  @moduledoc """
  GitHub discovery.

  Topic enumeration uses the **GraphQL API** (cursor paginated, newest-first)
  because the REST *search* API is limited to ~30 requests/minute, which makes
  broad topic crawls both slow and lossy. Code search must use REST and is
  rate-limit aware (it allows only ~10 requests/minute).
  """

  require Logger

  alias Helmscout.Http

  @per_page 100
  @max_retries 4
  @topic_concurrency 8
  @graphql_url "https://api.github.com/graphql"

  @topic_query """
  query($topic: String!, $cursor: String) {
    topic(name: $topic) {
      repositories(first: #{@per_page}, after: $cursor,
                   orderBy: {field: UPDATED_AT, direction: DESC}) {
        pageInfo { hasNextPage endCursor }
        nodes {
          nameWithOwner
          url
          stargazerCount
          pushedAt
          defaultBranchRef { name }
        }
      }
    }
  }
  """

  # --- topics -----------------------------------------------------------------

  @doc """
  Repositories tagged with any of `topics`.

  Uses GraphQL when a token is available (recommended), otherwise falls back to
  REST search.
  """
  @spec topics([String.t()], keyword()) :: [map()]
  def topics(topics, opts \\ []) do
    max_pages = Keyword.get(opts, :max_pages) || 10
    concurrency = Keyword.get(opts, :concurrency) || @topic_concurrency

    if Http.github_token() do
      Logger.info(
        "    github topics: #{length(topics)} topics via GraphQL (concurrency=#{concurrency})"
      )

      topics
      |> Task.async_stream(fn topic -> graphql_topic(topic, max_pages) end,
        max_concurrency: concurrency,
        timeout: 300_000,
        ordered: false,
        on_timeout: :kill_task
      )
      |> collect()
    else
      Logger.info("    github topics: no token, using REST search")
      rest_topics(topics, max_pages, concurrency)
    end
  end

  defp graphql_topic(topic, max_pages) do
    repos = graphql_page(topic, nil, 1, max_pages, [])
    Logger.info("      topic #{topic}: #{length(repos)} repos")
    repos
  end

  defp graphql_page(_topic, _cursor, page, max_pages, acc) when page > max_pages, do: acc

  defp graphql_page(topic, cursor, page, max_pages, acc) do
    case graphql(@topic_query, %{"topic" => topic, "cursor" => cursor}) do
      {:ok, %{"topic" => %{"repositories" => %{"nodes" => nodes} = conn}}} when is_list(nodes) ->
        acc = acc ++ Enum.map(nodes, &from_graphql(&1, "github_topic_graphql"))

        if get_in(conn, ["pageInfo", "hasNextPage"]) do
          graphql_page(topic, get_in(conn, ["pageInfo", "endCursor"]), page + 1, max_pages, acc)
        else
          acc
        end

      {:ok, %{"topic" => nil}} ->
        []

      {:error, reason} ->
        Logger.warning("      github topic #{topic} page #{page} failed: #{inspect(reason)}")
        acc
    end
  end

  @doc """
  Run a GraphQL query with rate-limit backoff.

  Returns `{:ok, data}` or `{:error, reason}`.
  """
  @spec graphql(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def graphql(query, variables, attempt \\ 1) do
    case Http.post_json(@graphql_url, %{"query" => query, "variables" => variables},
           headers: Http.github_headers()
         ) do
      {:ok, %{"data" => data}} when is_map(data) ->
        {:ok, data}

      {:ok, %{"errors" => errors}} ->
        retry_or_error(errors, query, variables, attempt)

      {:ok, other} ->
        {:error, other}

      {:error, {status, _body}} when status in [403, 429] ->
        retry_or_error(:rate_limited, query, variables, attempt)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp retry_or_error(reason, query, variables, attempt) do
    if attempt <= @max_retries and (reason == :rate_limited or rate_limited?(reason)) do
      seconds = backoff(attempt)
      Logger.warning("      github GraphQL rate limited, sleeping #{seconds}s")
      Process.sleep(seconds * 1000)
      graphql(query, variables, attempt + 1)
    else
      {:error, reason}
    end
  end

  defp rate_limited?(errors) when is_list(errors) do
    Enum.any?(errors, fn
      %{"type" => "RATE_LIMITED"} ->
        true

      %{"message" => msg} when is_binary(msg) ->
        String.contains?(String.downcase(msg), "rate limit")

      _ ->
        false
    end)
  end

  defp rate_limited?(_), do: false

  defp backoff(attempt), do: min(attempt * 5, 60)

  @doc false
  def from_graphql(node, discoverer) do
    %{
      name: node["nameWithOwner"],
      url: node["url"],
      forge: "github",
      branch: get_in(node, ["defaultBranchRef", "name"]) || "main",
      stars: node["stargazerCount"] || 0,
      pushed_at: parse_time(node["pushedAt"]),
      topics: [],
      discoverer: discoverer
    }
  end

  # --- REST fallback (no token) ----------------------------------------------

  defp rest_topics(topics, max_pages, concurrency) do
    topics
    |> Task.async_stream(fn topic -> rest_topic(topic, 1, max_pages) end,
      max_concurrency: min(concurrency, 3),
      timeout: 300_000,
      ordered: false,
      on_timeout: :kill_task
    )
    |> collect()
  end

  defp rest_topic(_topic, page, max_pages) when page > max_pages, do: []

  defp rest_topic(topic, page, max_pages) do
    params = [q: "topic:#{topic}", per_page: @per_page, page: page, sort: "updated"]

    case Http.get("https://api.github.com/search/repositories",
           headers: Http.github_headers(),
           params: params
         ) do
      {:ok, %{"items" => items}} when is_list(items) ->
        repos = Enum.map(items, &from_repo(&1, topic))

        if length(items) < @per_page do
          repos
        else
          repos ++ rest_topic(topic, page + 1, max_pages)
        end

      {:error, {status, _}} when status in [403, 429] ->
        Logger.warning("      github search rate limited for #{topic}")
        []

      {:error, reason} ->
        Logger.warning("      github topic #{topic} page #{page} failed: #{inspect(reason)}")
        []
    end
  end

  defp from_repo(repo, topic) do
    %{
      name: repo["full_name"],
      url: repo["html_url"],
      forge: "github",
      branch: repo["default_branch"] || "main",
      stars: repo["stargazers_count"] || 0,
      pushed_at: parse_time(repo["pushed_at"]),
      topics: repo["topics"] || [topic],
      discoverer: "github_topic:#{topic}"
    }
  end

  # --- code search ------------------------------------------------------------

  @doc """
  Repositories containing a manifest matching a code-search query, e.g.
  `"kind: HelmRelease"`. Code search is limited to ~10 requests/minute; results
  are fetched with low concurrency and rate-limit retries.
  """
  @spec code([String.t()], keyword()) :: [map()]
  def code(queries, opts \\ []) do
    pages = Keyword.get(opts, :pages) || 3
    concurrency = Keyword.get(opts, :concurrency) || 2

    queries
    |> Task.async_stream(fn query -> search_code(query, 1, pages) end,
      max_concurrency: concurrency,
      timeout: 300_000,
      ordered: false,
      on_timeout: :kill_task
    )
    |> collect()
  end

  defp search_code(_query, page, pages) when page > pages, do: []

  defp search_code(query, page, pages) do
    params = [q: query, per_page: @per_page, page: page]

    case Http.get("https://api.github.com/search/code",
           headers: Http.github_headers(),
           params: params
         ) do
      {:ok, %{"items" => items}} when is_list(items) ->
        repos = items |> Enum.map(&from_code_result/1) |> Enum.reject(&is_nil/1)

        if length(items) < @per_page do
          repos
        else
          repos ++ search_code(query, page + 1, pages)
        end

      {:ok, _} ->
        []

      {:error, {status, _}} when status in [403, 429] ->
        Logger.warning("      github code search rate limited, sleeping 60s")
        Process.sleep(60_000)
        []

      {:error, reason} ->
        Logger.warning("      github code search #{query} failed: #{inspect(reason)}")
        []
    end
  end

  defp from_code_result(%{"repository" => repo}) do
    %{
      name: repo["full_name"],
      url: repo["html_url"],
      forge: "github",
      branch: repo["default_branch"] || "main",
      stars: 0,
      pushed_at: parse_time(repo["pushed_at"]),
      topics: [],
      discoverer: "github_code"
    }
  end

  defp from_code_result(_), do: nil

  # --- helpers ----------------------------------------------------------------

  defp collect(stream) do
    Enum.flat_map(stream, fn
      {:ok, repos} -> repos
      _ -> []
    end)
  end

  @doc false
  def parse_time(nil), do: nil

  def parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  def parse_time(_), do: nil
end
