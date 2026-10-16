defmodule HelmscoutWeb.SearchController do
  @moduledoc false

  use HelmscoutWeb, :controller

  alias Helmscout.Search

  def home(conn, _params) do
    json(conn, Search.home_payload())
  end

  def apps(conn, params) do
    json(conn, %{apps: Search.apps(params)})
  end

  def app(conn, %{"app" => app}) do
    json(conn, %{
      app: app,
      summary: Search.app_summary(app),
      releases: Search.releases_for_app(app, 300) |> Enum.map(&release_json/1)
    })
  end

  def recommendations(conn, %{"app" => app}) do
    json(conn, %{rows: Search.recommendations(app)})
  end

  def random(conn, _params) do
    json(conn, Search.random())
  end

  def not_found(conn, _params) do
    conn |> put_status(:not_found) |> json(%{error: "not found"})
  end

  def stats(conn, _params) do
    json(conn, Search.stats())
  end

  def popular(conn, params) do
    limit = parse_limit(params["limit"], 50)
    json(conn, %{charts: Search.popular(limit)})
  end

  def charts(conn, params) do
    json(conn, %{charts: Search.charts(params)})
  end

  def releases(conn, params) do
    json(conn, %{releases: Search.releases(params)})
  end

  def values(conn, %{"id" => id}) do
    case Integer.parse(id) do
      {int, _} ->
        case Search.values(int) do
          nil -> conn |> put_status(:not_found) |> json(%{error: "release not found"})
          result -> json(conn, serialize_values(result))
        end

      :error ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid id"})
    end
  end

  def sources(conn, params) do
    json(conn, %{sources: Enum.map(Search.sources(params), &serialize_source/1)})
  end

  defp release_json(%{release: release, source: source}) do
    Map.merge(release, %{source: source})
  end

  defp serialize_values(%{release: release, values: values}) do
    %{
      id: release.id,
      release_name: release.release_name,
      chart_name: release.chart_name,
      chart_version: release.chart_version,
      namespace: release.namespace,
      scanner: release.scanner,
      file_url: release.file_url,
      commit_ts: release.commit_ts,
      source: serialize_source(release.source),
      values: values
    }
  end

  defp serialize_source(source) do
    %{
      id: source.id,
      name: source.name,
      url: source.url,
      forge: source.forge,
      branch: source.branch,
      stars: source.stars,
      release_count: source.release_count,
      last_indexed_at: source.last_indexed_at
    }
  end

  defp parse_limit(nil, default), do: default

  defp parse_limit(value, default) do
    case Integer.parse(to_string(value)) do
      {int, _} when int > 0 -> min(int, 500)
      _ -> default
    end
  end
end
