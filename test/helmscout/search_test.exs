defmodule Helmscout.SearchTest do
  use ExUnit.Case

  import Ecto.Query

  alias Helmscout.{HelmRelease, Repo, Search, Source}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    alpha =
      Repo.insert!(%Source{
        key: "alpha/home-ops",
        name: "alpha/home-ops",
        url: "https://github.com/alpha/home-ops",
        stars: 10
      })

    beta =
      Repo.insert!(%Source{
        key: "beta/home-ops",
        name: "beta/home-ops",
        url: "https://gitlab.com/beta/home-ops",
        forge: "gitlab",
        stars: 90
      })

    insert_release(alpha, %{
      chart_name: "immich",
      namespace: "media",
      scanner: "flux_helm_release"
    })

    insert_release(alpha, %{
      chart_name: "immich",
      namespace: "media",
      scanner: "flux_helm_release"
    })

    insert_release(beta, %{
      chart_name: "grafana",
      namespace: "monitoring",
      scanner: "argo_application"
    })

    :ok
  end

  defp insert_release(source, attrs) do
    defaults = %{
      source_id: source.id,
      release_name: attrs.chart_name,
      chart_name: "chart",
      scanner: "flux_helm_release",
      file_path: "app.yaml",
      file_url: "https://example.com/app.yaml",
      lines: 10,
      commit_ts: DateTime.truncate(DateTime.utc_now(), :second)
    }

    Repo.insert!(struct(HelmRelease, Map.merge(defaults, attrs)))
  end

  test "stats counts sources, releases and distinct charts" do
    stats = Search.stats()
    assert stats.sources == 2
    assert stats.releases == 3
    assert stats.charts == 2
  end

  test "popular ranks charts by deployment count" do
    assert [%{chart: "immich", releases: 2, sources: 1} | _] = Search.popular(10)
  end

  test "charts can be filtered and aggregated" do
    assert [%{chart: "grafana", releases: 1}] = Search.charts(%{"q" => "graf"})
  end

  test "releases filter by chart and join the source" do
    releases = Search.releases(%{"chart" => "immich", "limit" => "10"})
    assert length(releases) == 2
    assert Enum.all?(releases, fn %{source: s} -> s.name == "alpha/home-ops" end)
  end

  test "releases can be filtered by scanner and source" do
    assert [%{release: %{chart_name: "grafana"}}] =
             Search.releases(%{
               "scanner" => "argo_application",
               "source" => "beta",
               "limit" => "10"
             })
  end

  test "releases can be filtered by forge" do
    assert [%{release: %{chart_name: "grafana"}}] =
             Search.releases(%{"forge" => "gitlab", "limit" => "10"})

    assert [%{release: %{chart_name: "immich"}}, %{release: %{chart_name: "immich"}}] =
             Search.releases(%{"forge" => "github", "limit" => "10"})
  end

  test "values returns decoded JSON" do
    [%{release: release} | _] = Search.releases(%{"chart" => "immich", "limit" => "1"})

    Repo.update_all(
      from(r in HelmRelease, where: r.id == ^release.id),
      set: [values: ~s({"a":{"b":1}})]
    )

    assert %{values: %{"a" => %{"b" => 1}}} = Search.values(release.id)
  end
end
