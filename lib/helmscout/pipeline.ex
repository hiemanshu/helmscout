defmodule Helmscout.Pipeline do
  @moduledoc """
  End-to-end orchestration: discover repositories, persist them, then fetch and
  index each one.

  Long operations log progress as they go so a run can be watched live (see the
  `mix helmscout.*` tasks).
  """

  require Logger

  import Ecto.Query

  alias Helmscout.{Discovery, Fetch, Indexer, Progress, Repo, Source}

  @doc """
  Full update. Options:

    * `:max_age_days`, `:topics`, `:sources` - forwarded to `Discovery.run/1`
    * `:concurrency` - parallel clones/indexers (default 6)
    * `:limit` - maximum number of sources to index this run
    * `:only_stale_days` - only re-index sources older than this
  """
  @spec update(keyword()) :: map()
  def update(opts \\ []) do
    # Discovery and indexing have different sweet spots for concurrency, so only
    # forward discovery-relevant options here (indexing reads `:concurrency`).
    discovery_opts =
      opts
      |> Keyword.take([:max_age_days, :topics, :sources, :max_pages, :discovery_concurrency])
      |> maybe_put_concurrency(opts[:discovery_concurrency])

    candidates = Discovery.run(discovery_opts)
    persist_stats = Discovery.persist(candidates)

    sources = select_sources(opts)
    index_stats = index_sources(sources, opts)

    Map.merge(persist_stats, index_stats)
  end

  defp maybe_put_concurrency(opts, nil), do: opts

  defp maybe_put_concurrency(opts, concurrency),
    do: Keyword.put(opts, :concurrency, concurrency)

  @doc "Fetch and index the given sources (or all sources when omitted)."
  @spec index_all(keyword()) :: map()
  def index_all(opts \\ []) do
    opts |> select_sources() |> index_sources(opts)
  end

  @doc "Fetch and index a specific list of `%Source{}` structs."
  @spec index_sources([Source.t()], keyword()) :: map()
  def index_sources(sources, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency) || System.schedulers_online()
    cache_dir = Keyword.get(opts, :cache_dir)
    total = length(sources)

    Logger.info("indexing #{total} sources (concurrency=#{concurrency})")

    progress = Progress.start("indexing", total)

    {progress, results} =
      sources
      |> Task.async_stream(&index_one(&1, cache_dir, opts),
        max_concurrency: concurrency,
        timeout: 600_000,
        ordered: false,
        on_timeout: :kill_task
      )
      |> Enum.reduce({progress, []}, fn item, {progress, acc} ->
        result = normalize(item)
        progress = Progress.update(progress, result, detail(result))
        {progress, [result | acc]}
      end)

    Progress.finish(progress)

    stats = tally(results, total)

    Logger.info(
      "indexing complete: ok=#{stats.ok} empty=#{stats.empty} skipped=#{stats.skipped} " <>
        "error=#{stats.error} releases=#{stats.releases}"
    )

    stats
  end

  defp index_one(source, cache_dir, opts) do
    started = System.monotonic_time(:millisecond)

    result =
      cond do
        not Keyword.get(opts, :force, false) and unchanged?(source) ->
          %{status: :skipped, releases: 0}

        true ->
          do_index(source, cache_dir)
      end

    Map.merge(result, %{
      name: source.name,
      duration_ms: System.monotonic_time(:millisecond) - started
    })
  rescue
    e -> %{status: :error, releases: 0, name: source.name, reason: e, duration_ms: 0}
  end

  # Skip when the default branch has not moved since the last index. A cheap
  # `pushed_at` check avoids a network call for most repositories; otherwise we
  # compare the remote HEAD sha (still no clone).
  defp unchanged?(source) do
    cond do
      is_nil(source.last_indexed_at) ->
        false

      source.pushed_at != nil and
          DateTime.compare(source.pushed_at, source.last_indexed_at) != :gt ->
        true

      true ->
        sha_unchanged?(source)
    end
  end

  defp sha_unchanged?(source) do
    with sha when is_binary(sha) <- source.last_commit_sha,
         {:ok, remote} <- Fetch.remote_head(source) do
      remote == sha
    else
      _ -> false
    end
  end

  defp do_index(source, cache_dir) do
    case Fetch.checkout(source, cache_dir: cache_dir) do
      {:ok, dir} ->
        case Indexer.index_source(source, dir: dir) do
          {:ok, 0} -> %{status: :empty, releases: 0}
          {:ok, count} -> %{status: :ok, releases: count}
          {:error, reason} -> %{status: :error, releases: 0, reason: reason}
        end

      {:error, reason} ->
        %{status: :error, releases: 0, reason: reason}
    end
  end

  defp normalize({:ok, result}), do: result

  defp normalize({:exit, reason}),
    do: %{status: :error, releases: 0, name: "?", reason: reason, duration_ms: 0}

  defp detail(%{status: status, name: name} = result) do
    "#{status_label(status)} #{name} -> #{result[:releases] || 0} releases (#{result[:duration_ms] || 0}ms)"
  end

  defp status_label(:ok), do: "ok    "
  defp status_label(:empty), do: "empty "
  defp status_label(:skipped), do: "skip  "
  defp status_label(_), do: "error "

  defp tally(results, total) do
    Enum.reduce(
      results,
      %{total: total, ok: 0, empty: 0, error: 0, skipped: 0, releases: 0},
      fn r, acc ->
        acc
        |> Map.update!(:releases, &(&1 + r.releases))
        |> Map.update!(r.status, &(&1 + 1))
      end
    )
  end

  defp select_sources(opts) do
    limit = Keyword.get(opts, :limit)
    only_stale = Keyword.get(opts, :only_stale_days)

    query =
      from(s in Source, order_by: [desc: s.stars])

    query =
      if only_stale do
        cutoff = DateTime.add(DateTime.utc_now(), -only_stale, :day)
        from(s in query, where: is_nil(s.last_indexed_at) or s.last_indexed_at < ^cutoff)
      else
        query
      end

    query = if limit, do: from(s in query, limit: ^limit), else: query

    Repo.all(query)
  end
end
