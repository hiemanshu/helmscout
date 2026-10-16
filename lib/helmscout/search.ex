defmodule Helmscout.Search do
  @moduledoc """
  Read queries backing the HTTP API and the MCP server.

  All listing queries join the owning source and never load the potentially
  large `values` blob unless explicitly requested.
  """

  import Ecto.Query

  alias Helmscout.{HelmRelease, Repo, Source}

  @generic_apps ~w(app-template common library raw default chart)

  # Owner opt-out filtering. `scope` is `:api` (the site reads /api) or `:mcp`.
  defp visible(query, scope) do
    ids = Helmscout.Visibility.excluded_ids(scope)
    where(query, [r], r.source_id not in ^ids)
  end

  defp visible_sources(query, scope) do
    ids = Helmscout.Visibility.excluded_ids(scope)
    where(query, [s], s.id not in ^ids)
  end

  @doc "High-level index statistics."
  def stats(scope \\ :api) do
    ids = Helmscout.Visibility.excluded_ids(scope)

    source_count =
      Repo.one(from s in Source, where: s.id not in ^ids, select: count(s.id))

    release_count =
      Repo.one(from r in HelmRelease, where: r.source_id not in ^ids, select: count(r.id))

    chart_count =
      Repo.one(
        from r in HelmRelease,
          where: r.source_id not in ^ids,
          select: count(r.chart_name, :distinct)
      )

    scanner_breakdown =
      Repo.all(
        from r in HelmRelease,
          where: r.source_id not in ^ids,
          group_by: r.scanner,
          select: %{scanner: r.scanner, count: count(r.id)},
          order_by: [desc: count(r.id)]
      )

    last_indexed =
      Repo.one(from s in Source, where: s.id not in ^ids, select: max(s.last_indexed_at))

    app_count =
      Repo.one(
        from r in HelmRelease,
          where: r.source_id not in ^ids and not is_nil(r.app) and r.app not in ^@generic_apps,
          select: count(r.app, :distinct)
      )

    forge_breakdown =
      Repo.all(
        from s in Source,
          where: s.id not in ^ids,
          group_by: s.forge,
          select: %{forge: s.forge, count: count(s.id)},
          order_by: [desc: count(s.id)]
      )

    %{
      sources: source_count,
      releases: release_count,
      charts: chart_count,
      apps: app_count,
      last_indexed_at: last_indexed,
      scanners: scanner_breakdown,
      forges: forge_breakdown
    }
  end

  @doc "Minimum data to render the home page (top apps + discover pool + counts)."
  def home_payload(scope \\ :api) do
    %{
      stats: stats(scope) |> Map.take([:sources, :releases, :charts, :apps, :last_indexed_at]),
      top_apps: top_apps(20, scope) |> Enum.map(&Map.take(&1, [:app, :releases, :sources])),
      discover_pool:
        discover_pool(1, 6, scope)
        |> Enum.take(1000)
        |> Enum.map(&Map.take(&1, [:app, :releases]))
    }
  end

  @doc "Deployment summary for one app (counts)."
  def app_summary(app, scope \\ :api) do
    from(r in HelmRelease,
      where: r.app == ^app,
      select: %{
        releases: count(r.id),
        sources: count(r.source_id, :distinct),
        last_seen: max(r.commit_ts)
      }
    )
    |> visible(scope)
    |> Repo.one()
    |> case do
      nil -> %{releases: 0, sources: 0, last_seen: nil}
      summary -> summary
    end
  end

  @doc "Most common settings across an app's installs."
  def recommendations(app, scope \\ :api), do: Helmscout.Recommendations.for_app(app, scope)

  @doc "A random app, or a random repository — for 'surprise me'."
  def random do
    if :rand.uniform(2) == 1 do
      case random_app() do
        nil -> source_or_none()
        app -> %{type: "app", value: app}
      end
    else
      case random_source() do
        nil -> app_or_none()
        source -> %{type: "source", value: source}
      end
    end
  end

  defp source_or_none do
    case random_source() do
      nil -> %{type: "none", value: nil}
      source -> %{type: "source", value: source}
    end
  end

  defp app_or_none do
    case random_app() do
      nil -> %{type: "none", value: nil}
      app -> %{type: "app", value: app}
    end
  end

  @doc "A random app name (excluding generic/templated identities), or nil."
  def random_app(scope \\ :api) do
    ids = Helmscout.Visibility.excluded_ids(scope)

    Repo.one(
      from r in HelmRelease,
        where: not is_nil(r.app) and r.app != "" and r.source_id not in ^ids,
        select: r.app,
        order_by: fragment("RANDOM()"),
        limit: 1
    )
    |> exclude_bad_apps()
  end

  defp exclude_bad_apps(nil), do: nil

  defp exclude_bad_apps(app) do
    if app =~ ~r/[${\/<>]|^\.|\s|__/ do
      random_app()
    else
      app
    end
  end

  defp random_source(scope \\ :api) do
    ids = Helmscout.Visibility.excluded_ids(scope)

    Repo.one(
      from s in Source,
        where: s.release_count > 0 and s.id not in ^ids,
        select: s.name,
        order_by: fragment("RANDOM()"),
        limit: 1
    )
  end

  @doc "Most-deployed charts across the index."
  def popular(limit \\ 50, scope \\ :api) do
    from(r in HelmRelease,
      group_by: r.chart_name,
      select: %{
        chart: r.chart_name,
        releases: count(r.id),
        sources: count(r.source_id, :distinct),
        last_seen: max(r.commit_ts)
      },
      order_by: [desc: count(r.id)],
      limit: ^limit
    )
    |> visible(scope)
    |> Repo.all()
  end

  @doc "Chart names with aggregate counts, optionally filtered by name."
  def charts(params \\ %{}, scope \\ :api) do
    q = blank_to_nil(params["q"])
    limit = clamp(params["limit"], 50, 1, 500)
    offset = clamp(params["offset"], 0, 0, 100_000)

    query =
      from r in HelmRelease,
        group_by: r.chart_name,
        select: %{
          chart: r.chart_name,
          releases: count(r.id),
          sources: count(r.source_id, :distinct),
          last_seen: max(r.commit_ts)
        },
        order_by: [desc: count(r.id), asc: r.chart_name],
        limit: ^limit,
        offset: ^offset

    query
    |> visible(scope)
    |> maybe_where_chart(q)
    |> Repo.all()
  end

  @doc "List individual Helm releases matching the given filters."
  def releases(params \\ %{}, scope \\ :api) do
    limit = clamp(params["limit"], 50, 1, 500)
    offset = clamp(params["offset"], 0, 0, 100_000)
    include_values = truthy?(params["include_values"])

    base =
      from r in HelmRelease,
        join: s in assoc(r, :source),
        limit: ^limit,
        offset: ^offset

    base
    |> visible(scope)
    |> filter_release(params)
    |> order_releases(params["sort"])
    |> select_release(include_values)
    |> Repo.all()
  end

  defp order_releases(query, "recent"),
    do: order_by(query, [r, _s], desc: r.commit_ts, desc: r.id)

  defp order_releases(query, "name"), do: order_by(query, [r, _s], asc: r.app, asc: r.chart_name)

  defp order_releases(query, _),
    do: order_by(query, [r, s], desc: s.stars, desc: r.commit_ts, desc: r.id)

  @doc "All releases of a specific chart (exact name), newest first."
  def releases_for_chart(chart, limit \\ 100, scope \\ :api) do
    from(r in HelmRelease,
      join: s in assoc(r, :source),
      where: r.chart_name == ^chart,
      order_by: [desc: r.commit_ts, desc: r.id],
      limit: ^limit
    )
    |> visible(scope)
    |> select_release(false)
    |> Repo.all()
  end

  # App names that are not a real identity: template variables (`${app}-foo`),
  # local chart paths (`./charts/foo`), or empty-ish values.
  defp real_app(query) do
    where(
      query,
      [r],
      fragment(
        """
        ? NOT LIKE '%$%' AND ? NOT LIKE '%{%' AND ? NOT LIKE '%}%'
        AND ? NOT LIKE '%/%' AND ? NOT LIKE '.%' AND ? NOT LIKE '% %'
        AND ? NOT LIKE '%<%' AND ? NOT LIKE '%>%' AND instr(?, '__') = 0
        """,
        r.app,
        r.app,
        r.app,
        r.app,
        r.app,
        r.app,
        r.app,
        r.app,
        r.app
      )
    )
  end

  @doc "Most-deployed *apps* (image/chart identity), excluding generic charts."
  def top_apps(limit \\ 40, scope \\ :api) do
    from(r in HelmRelease,
      where: not is_nil(r.app) and r.app not in ^@generic_apps,
      group_by: r.app,
      select: %{
        app: r.app,
        releases: count(r.id),
        sources: count(r.source_id, :distinct),
        last_seen: max(r.commit_ts)
      },
      order_by: [desc: count(r.id), asc: r.app],
      limit: ^limit
    )
    |> real_app()
    |> visible(scope)
    |> Repo.all()
  end

  @doc "Apps with a small number of deployments — the pool for 'Discover'."
  def discover_pool(min \\ 1, max \\ 6, scope \\ :api) do
    from(r in HelmRelease,
      where: not is_nil(r.app) and r.app not in ^@generic_apps,
      group_by: r.app,
      having: count(r.id) >= ^min and count(r.id) <= ^max,
      select: %{app: r.app, releases: count(r.id)}
    )
    |> real_app()
    |> visible(scope)
    |> Repo.all()
  end

  @doc "All releases of a specific app (exact name), newest first."
  def releases_for_app(app, limit \\ 200, scope \\ :api) do
    from(r in HelmRelease,
      join: s in assoc(r, :source),
      where: r.app == ^app,
      order_by: [desc: r.commit_ts, desc: r.id],
      limit: ^limit
    )
    |> visible(scope)
    |> select_release(false)
    |> Repo.all()
  end

  @doc "Apps with aggregate counts, optionally filtered by name."
  def apps(params \\ %{}, scope \\ :api) do
    q = blank_to_nil(params["q"])
    limit = clamp(params["limit"], 100, 1, 1000)
    offset = clamp(params["offset"], 0, 0, 100_000)

    query =
      from r in HelmRelease,
        where: not is_nil(r.app),
        group_by: r.app,
        select: %{
          app: r.app,
          releases: count(r.id),
          sources: count(r.source_id, :distinct),
          last_seen: max(r.commit_ts)
        },
        order_by: [desc: count(r.id), asc: r.app],
        limit: ^limit,
        offset: ^offset

    query =
      if q, do: where(query, [r], fragment("lower(?) LIKE ?", r.app, ^like(q))), else: query

    query |> real_app() |> visible(scope) |> Repo.all()
  end

  @doc "Fetch one release (with decoded values) by id."
  def values(id, scope \\ :api) do
    ids = Helmscout.Visibility.excluded_ids(scope)

    case Repo.one(
           from r in HelmRelease,
             where: r.id == ^id and r.source_id not in ^ids,
             preload: [:source]
         ) do
      nil -> nil
      release -> %{release: release, values: HelmRelease.decoded_values(release)}
    end
  end

  @doc "List sources with their release counts."
  def sources(params \\ %{}, scope \\ :api) do
    limit = clamp(params["limit"], 100, 1, 1000)
    offset = clamp(params["offset"], 0, 0, 100_000)

    from(s in Source,
      order_by: [desc: s.release_count, desc: s.stars, asc: s.name],
      limit: ^limit,
      offset: ^offset
    )
    |> visible_sources(scope)
    |> maybe_where_source(blank_to_nil(params["q"]))
    |> maybe_where_forge(blank_to_nil(params["forge"]))
    |> maybe_where_indexed(truthy?(params["with_releases"]))
    |> Repo.all()
  end

  defp maybe_where_forge(query, nil), do: query
  defp maybe_where_forge(query, forge), do: where(query, [s], s.forge == ^forge)

  defp maybe_where_indexed(query, true), do: where(query, [s], s.release_count > 0)
  defp maybe_where_indexed(query, _), do: query

  # --- query building ---------------------------------------------------------

  defp filter_release(query, params) do
    query
    |> maybe_where_free_text(blank_to_nil(params["q"]))
    |> then(fn query ->
      Enum.reduce(
        [
          {"chart", :chart_name, :like},
          {"source", :source_name, :like},
          {"namespace", :namespace, :like},
          {"scanner", :scanner, :eq},
          {"forge", :forge, :eq}
        ],
        query,
        fn {key, _field, _mode}, acc ->
          case blank_to_nil(params[key]) do
            nil -> acc
            value -> apply_filter(acc, key, value)
          end
        end
      )
    end)
  end

  # Free-text search across the app name, chart and release name.
  defp maybe_where_free_text(query, nil), do: query

  defp maybe_where_free_text(query, q) do
    like = like(q)

    where(
      query,
      [r, _s],
      fragment(
        "lower(?) LIKE ? OR lower(?) LIKE ? OR lower(?) LIKE ?",
        r.app,
        ^like,
        r.chart_name,
        ^like,
        r.release_name,
        ^like
      )
    )
  end

  defp apply_filter(query, "chart", value) do
    where(query, [r, _s], fragment("lower(?) LIKE ?", r.chart_name, ^like(value)))
  end

  defp apply_filter(query, "source", value) do
    where(query, [_r, s], fragment("lower(?) LIKE ?", s.name, ^like(value)))
  end

  defp apply_filter(query, "namespace", value) do
    where(query, [r, _s], fragment("lower(?) LIKE ?", r.namespace, ^like(value)))
  end

  defp apply_filter(query, "scanner", value) do
    where(query, [r, _s], r.scanner == ^value)
  end

  defp apply_filter(query, "forge", value) do
    where(query, [_r, s], s.forge == ^value)
  end

  defp select_release(query, include_values) do
    if include_values do
      from [r, s] in query,
        select: %{
          release: %{
            id: r.id,
            release_name: r.release_name,
            chart_name: r.chart_name,
            chart_version: r.chart_version,
            namespace: r.namespace,
            chart_ref_kind: r.chart_ref_kind,
            chart_source: r.chart_source,
            scanner: r.scanner,
            icon: r.icon,
            group: r.group,
            app: r.app,
            file_path: r.file_path,
            file_url: r.file_url,
            lines: r.lines,
            commit_ts: r.commit_ts,
            values: r.values
          },
          source: map(s, [:id, :name, :url, :forge, :stars, :branch])
        }
    else
      from [r, s] in query,
        select: %{
          release: %{
            id: r.id,
            release_name: r.release_name,
            chart_name: r.chart_name,
            chart_version: r.chart_version,
            namespace: r.namespace,
            chart_ref_kind: r.chart_ref_kind,
            chart_source: r.chart_source,
            scanner: r.scanner,
            icon: r.icon,
            group: r.group,
            app: r.app,
            file_path: r.file_path,
            file_url: r.file_url,
            lines: r.lines,
            commit_ts: r.commit_ts
          },
          source: map(s, [:id, :name, :url, :forge, :stars, :branch])
        }
    end
  end

  defp maybe_where_chart(query, nil), do: query

  defp maybe_where_chart(query, q) do
    where(query, [r], fragment("lower(?) LIKE ?", r.chart_name, ^like(q)))
  end

  defp maybe_where_source(query, nil), do: query

  defp maybe_where_source(query, q) do
    where(query, [s], fragment("lower(?) LIKE ?", s.name, ^like(q)))
  end

  defp like(value), do: "%" <> String.downcase(String.trim(value)) <> "%"

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(to_string(value)) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp truthy?(value), do: value in [true, "true", "1", 1, "yes"]

  defp clamp(nil, default, min, max), do: clamp(default, default, min, max)

  defp clamp(value, _default, min, max) do
    case Integer.parse(to_string(value)) do
      {int, _} -> int |> Kernel.max(min) |> Kernel.min(max)
      :error -> min
    end
  end
end
