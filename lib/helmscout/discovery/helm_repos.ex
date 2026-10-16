defmodule Helmscout.Discovery.HelmRepos do
  @moduledoc """
  Exhaustive discovery of repositories that contain HelmRelease-style manifests,
  using **sharded GitHub code search**.

  Code search returns at most 1000 results per query and cannot sort by creation
  date, so a single query misses most repositories. We work around that by
  partitioning the search space with `created:` date windows and recursively
  splitting any window that saturates the 1000-result cap. Results are then
  de-duplicated by the orchestrator.

  Code search is limited to ~10 requests/minute, so this is a **slow backfill**
  source (opt in with `--sources helm_repos`). Concurrency is intentionally 1
  and requests are throttled.
  """

  require Logger

  alias Helmscout.Http

  @per_page 100
  @page_cap 10

  @default_queries [
    ~s("kind: HelmRelease" helm.toolkit.fluxcd.io),
    ~s("kind: Application" argoproj.io)
  ]

  @spec candidates(keyword()) :: [map()]
  def candidates(opts \\ []) do
    queries = Keyword.get(opts, :queries) || @default_queries
    start_date = Keyword.get(opts, :start_date) || ~D[2018-01-01]
    max_depth = Keyword.get(opts, :max_depth) || 2
    rate = Keyword.get(opts, :rate_per_minute) || 8
    throttle_ms = round(60_000 / rate)

    Logger.info(
      "      helm_repos: sharded code search (#{length(queries)} queries, " <>
        "#{rate} req/min, depth<=#{max_depth})"
    )

    Enum.reduce(queries, [], fn query, acc ->
      repos =
        search_window(query, start_date, Date.utc_today(), 0, max_depth, throttle_ms)

      Logger.info("      helm_repos #{query}: #{length(repos)} repos")
      acc ++ repos
    end)
  end

  # --- windowed search --------------------------------------------------------

  defp search_window(query, from, to, depth, max_depth, throttle) do
    q = "#{query} created:#{Date.to_iso8601(from)}..#{Date.to_iso8601(to)} fork:false"
    {results, saturated?} = search_all_pages(q, 1, [], throttle)

    cond do
      not saturated? ->
        results

      depth >= max_depth ->
        results

      Date.diff(to, from) < 1 ->
        results

      true ->
        m = mid(from, to)

        search_window(query, from, m, depth + 1, max_depth, throttle) ++
          search_window(query, Date.add(m, 1), to, depth + 1, max_depth, throttle)
    end
  end

  defp mid(from, to), do: Date.add(from, div(Date.diff(to, from), 2))

  defp search_all_pages(_query, page, acc, _throttle) when page > @page_cap, do: {acc, true}

  defp search_all_pages(query, page, acc, throttle) do
    throttle(throttle)
    params = [q: query, per_page: @per_page, page: page]

    case Http.get("https://api.github.com/search/code",
           headers: Http.github_headers(),
           params: params
         ) do
      {:ok, %{"items" => items}} when is_list(items) ->
        acc = acc ++ (items |> Enum.map(&from_code_result/1) |> Enum.reject(&is_nil/1))

        cond do
          length(items) < @per_page -> {acc, false}
          page == @page_cap -> {acc, true}
          true -> search_all_pages(query, page + 1, acc, throttle)
        end

      {:error, {status, _}} when status in [403, 429] ->
        Logger.warning("      helm_repos: code search rate limited, backing off 60s")
        Process.sleep(60_000)
        search_all_pages(query, page, acc, throttle)

      {:error, reason} ->
        Logger.warning("      helm_repos: page #{page} failed: #{inspect(reason)}")
        {acc, false}
    end
  end

  defp throttle(ms) when ms > 0, do: Process.sleep(ms)
  defp throttle(_), do: :ok

  defp from_code_result(%{"repository" => repo}) do
    %{
      name: repo["full_name"],
      url: repo["html_url"],
      forge: "github",
      branch: repo["default_branch"] || "main",
      stars: 0,
      pushed_at: Helmscout.Discovery.Github.parse_time(repo["pushed_at"]),
      topics: [],
      discoverer: "helm_repos"
    }
  end

  defp from_code_result(_), do: nil
end
