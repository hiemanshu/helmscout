defmodule Helmscout.Discovery do
  @moduledoc """
  Finds candidate repositories across forges, merges duplicates and persists
  them as `Helmscout.Source` rows.

  Sources run concurrently and are individually fault-tolerant: a failing forge
  only costs its own results.
  """

  require Logger

  alias Helmscout.{Repo, Source}
  alias Helmscout.Discovery.{Awesome, Curated, Gitea, Github, Gitlab, HelmRepos, Users}

  @default_topics ~w(
    k8s-at-home
    kubesearch
    helmscout
    kubernetes-at-home
    fluxcd
    flux
    home-ops
    homeops
    gitops
    homelab
    talos
    k3s
  )

  @default_code_queries [
    "\"kind: HelmRelease\" helm.toolkit.fluxcd.io",
    "\"kind: Application\" argoproj.io"
  ]

  @doc """
  Discover candidate repositories. Options:

    * `:max_age_days` - drop repos whose last push is older than this (default 120)
    * `:topics` - override the GitHub/GitLab topic list
    * `:code_queries` - override the GitHub code-search queries
    * `:sources` - subset of source names to run (e.g. `[:curated, :github_topics]`)
  """
  @spec run(keyword()) :: [map()]
  def run(opts \\ []) do
    # Callers (e.g. the update task) may pass keys with nil values; drop them so
    # the defaults below actually apply.
    opts = Enum.reject(opts, fn {_key, value} -> is_nil(value) end)

    max_age = Keyword.get(opts, :max_age_days, 120)

    selected =
      Keyword.get(opts, :sources, [
        :curated,
        :users,
        :github_topics,
        :github_code,
        :gitlab,
        :gitea,
        :awesome
      ])

    topics = Keyword.get(opts, :topics, configured_topics())
    code_queries = Keyword.get(opts, :code_queries, @default_code_queries)
    per_source_opts = Keyword.take(opts, [:max_pages, :concurrency])

    Logger.info("discovery starting (sources=#{inspect(selected)}, topics=#{length(topics)})")

    candidates =
      selected
      |> Enum.map(&task_for(&1, topics, code_queries, per_source_opts))
      |> Task.async_stream(&run_source/1, timeout: 600_000, ordered: false)
      |> Enum.flat_map(fn
        {:ok, {_name, candidates}} -> candidates
        _ -> []
      end)

    merged = merge(candidates)
    kept = merged |> deny_filter() |> filter_recency(max_age)

    :telemetry.execute([:helmscout, :discovery, :repos_found], %{total: length(kept)}, %{})

    Logger.info(
      "discovery found #{length(candidates)} raw / #{length(kept)} after dedupe+recency"
    )

    kept
  end

  @doc "Persist candidates as sources (upsert by lower-cased key)."
  @spec persist([map()]) :: %{
          total: non_neg_integer(),
          inserted: non_neg_integer(),
          updated: non_neg_integer()
        }
  def persist(candidates) do
    existing = Repo.all(Source) |> Map.new(&{&1.key, &1})

    Enum.reduce(candidates, %{total: 0, inserted: 0, updated: 0}, fn candidate, acc ->
      key = Source.build_key(candidate.name)
      now = DateTime.utc_now()
      source = Map.get(existing, key)
      hide_mcp = Helmscout.Visibility.hide_mcp_from_topics?(candidate.topics)

      case source do
        nil ->
          attrs = Map.put(to_source_attrs(candidate, now), :hide_mcp, hide_mcp)
          Repo.insert!(Source.changeset(%Source{}, attrs))
          Map.update!(acc, :inserted, &(&1 + 1))

        source ->
          # `hide_mcp` is a union: the topic can add it but never clears a marker
          # file's opt-out.
          attrs =
            merge_into_source(source, candidate, now)
            |> Map.put(:hide_mcp, hide_mcp or source.hide_mcp)

          Repo.update!(Source.changeset(source, attrs))
          Map.update!(acc, :updated, &(&1 + 1))
      end
      |> Map.update!(:total, &(&1 + 1))
    end)
  end

  # --- source plumbing --------------------------------------------------------

  defp task_for(:curated, _topics, _code, _opts), do: {:curated, fn -> Curated.candidates() end}
  defp task_for(:awesome, _topics, _code, _opts), do: {:awesome, fn -> Awesome.candidates() end}

  defp task_for(:users, _topics, _code, opts),
    do: {:users, fn -> Users.candidates(opts) end}

  defp task_for(:helm_repos, _topics, _code, opts),
    do: {:helm_repos, fn -> HelmRepos.candidates(opts) end}

  defp task_for(:github_topics, topics, _code, opts),
    do: {:github_topics, fn -> Github.topics(topics, opts) end}

  defp task_for(:github_code, _topics, code, opts),
    do: {:github_code, fn -> Github.code(code, opts) end}

  defp task_for(:gitlab, topics, _code, opts),
    do: {:gitlab, fn -> Gitlab.topics(topics, opts) end}

  defp task_for(:gitea, topics, _code, opts), do: {:gitea, fn -> Gitea.topics(topics, opts) end}

  defp task_for(source, _topics, _code, _opts) do
    raise ArgumentError, "unknown discovery source: #{inspect(source)}"
  end

  defp run_source({name, fun}) do
    started = System.monotonic_time(:millisecond)
    candidates = fun.()

    Logger.info(
      "  #{name}: #{length(candidates)} candidates (#{System.monotonic_time(:millisecond) - started}ms)"
    )

    {name, candidates}
  rescue
    e ->
      Logger.warning("  #{name} source crashed: #{Exception.message(e)}")
      {name, []}
  end

  # --- merge + filtering ------------------------------------------------------

  @doc false
  def merge(candidates) do
    candidates
    |> Enum.reject(&(is_nil(&1.name) or &1.name == ""))
    |> Enum.group_by(&Source.build_key(&1.name))
    |> Enum.map(fn {_key, group} -> merge_group(group) end)
  end

  defp merge_group(group) do
    canonical = Enum.max_by(group, &(&1.stars || 0))

    %{
      name: canonical.name,
      url: canonical.url,
      forge: canonical.forge,
      branch: canonical.branch || "main",
      stars: Enum.max_by(group, &(&1.stars || 0)).stars || 0,
      pushed_at: group |> Enum.map(& &1.pushed_at) |> Enum.reject(&is_nil/1) |> max_or_nil(),
      topics: group |> Enum.flat_map(&(&1.topics || [])) |> Enum.uniq(),
      discoverers: group |> Enum.map(& &1.discoverer) |> Enum.uniq()
    }
  end

  @doc false
  def filter_recency(candidates, max_age) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age, :day)

    Enum.filter(candidates, fn c ->
      cond do
        "curated" in c.discoverers -> true
        is_nil(c.pushed_at) -> true
        DateTime.compare(c.pushed_at, cutoff) == :gt -> true
        true -> false
      end
    end)
  end

  # Chart catalogs (not deployment configs) flood the index with noise.
  @deny_patterns ["truecharts", "true_charts", "/charts"]
  @deny_exact ["k8s-at-home/charts", "bjw-s/helm-charts", "bjw-s-labs/helm-charts"]

  @doc false
  def deny_filter(candidates) do
    Enum.reject(candidates, fn c ->
      down = String.downcase(c.name)
      down in @deny_exact or Enum.any?(@deny_patterns, &String.contains?(down, &1))
    end)
  end

  # --- persistence helpers ----------------------------------------------------

  defp to_source_attrs(candidate, now) do
    %{
      key: Source.build_key(candidate.name),
      name: candidate.name,
      url: candidate.url,
      forge: candidate.forge,
      branch: candidate.branch || "main",
      stars: candidate.stars || 0,
      pushed_at: truncate_seconds(candidate.pushed_at),
      topics: candidate.topics || [],
      discoverers: candidate.discoverers || [candidate.discoverer],
      inserted_at: now,
      updated_at: now
    }
  end

  defp merge_into_source(source, candidate, now) do
    discoverers = Enum.uniq((source.discoverers || []) ++ (candidate.discoverers || []))
    topics = Enum.uniq((source.topics || []) ++ (candidate.topics || []))
    better? = (candidate.stars || 0) > (source.stars || 0)

    %{
      discoverers: discoverers,
      topics: topics,
      stars: max(source.stars || 0, candidate.stars || 0),
      pushed_at: truncate_seconds(later(source.pushed_at, candidate.pushed_at)),
      updated_at: now
    }
    |> maybe_replace_origin(source, candidate, better?)
  end

  defp maybe_replace_origin(attrs, source, candidate, true) do
    Map.merge(attrs, %{
      name: candidate.name,
      url: candidate.url,
      forge: candidate.forge,
      branch: candidate.branch || source.branch
    })
  end

  defp maybe_replace_origin(attrs, _source, _candidate, false), do: attrs

  defp later(nil, b), do: b
  defp later(a, nil), do: a

  defp later(a, b) do
    if DateTime.compare(a, b) == :lt, do: b, else: a
  end

  defp max_or_nil([]), do: nil
  defp max_or_nil(list), do: Enum.max_by(list, &DateTime.to_unix/1)

  defp truncate_seconds(nil), do: nil
  defp truncate_seconds(%DateTime{} = dt), do: DateTime.truncate(dt, :second)
  defp truncate_seconds(other), do: other

  defp configured_topics do
    case System.get_env("HELMSCOUT_TOPICS") do
      nil -> @default_topics
      "" -> @default_topics
      value -> value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    end
  end
end
