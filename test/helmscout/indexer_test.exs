defmodule Helmscout.IndexerTest do
  use ExUnit.Case

  import Ecto.Query

  alias Helmscout.{Indexer, Repo, Source}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    dir = Path.join(System.tmp_dir!(), "helmscout-indexer-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "apps/immich"))
    on_exit(fn -> File.rm_rf(dir) end)

    File.write!(Path.join(dir, "apps/immich/helmrelease.yaml"), """
    apiVersion: helm.toolkit.fluxcd.io/v2
    kind: HelmRelease
    metadata:
      name: immich
      namespace: media
    spec:
      chart:
        spec:
          chart: immich
          version: 9.0.0
          sourceRef:
            kind: HelmRepository
            name: bjw-s
      values:
        controllers:
          main:
            containers:
              main:
                image:
                  tag: v1.0.0
    """)

    File.write!(Path.join(dir, "README.md"), "# not a manifest")

    %{dir: dir}
  end

  test "index_source scans a checkout and persists releases", %{dir: dir} do
    source =
      Repo.insert!(%Source{
        key: "acme/home-ops",
        name: "acme/home-ops",
        url: "https://github.com/acme/home-ops"
      })

    assert {:ok, 1} = Indexer.index_source(source, dir: dir)

    reloaded = Repo.get!(Source, source.id)
    assert reloaded.release_count == 1
    assert reloaded.last_indexed_at

    [release] = Repo.all(from(r in Helmscout.HelmRelease, where: r.source_id == ^source.id))
    assert release.chart_name == "immich"
    assert release.namespace == "media"
    assert release.file_path == "apps/immich/helmrelease.yaml"

    assert release.file_url ==
             "https://github.com/acme/home-ops/blob/main/apps/immich/helmrelease.yaml"

    assert release.values =~ "v1.0.0"
  end

  test "file URLs are forge aware", %{dir: dir} do
    source =
      Repo.insert!(%Source{
        key: "acme/gitlab-ops",
        name: "acme/gitlab-ops",
        url: "https://gitlab.com/acme/gitlab-ops",
        forge: "gitlab"
      })

    assert {:ok, 1} = Indexer.index_source(source, dir: dir)

    [release] = Repo.all(from(r in Helmscout.HelmRelease, where: r.source_id == ^source.id))

    assert release.file_url ==
             "https://gitlab.com/acme/gitlab-ops/-/blob/main/apps/immich/helmrelease.yaml"
  end

  test "re-indexing replaces previous rows", %{dir: dir} do
    source =
      Repo.insert!(%Source{key: "acme/re", name: "acme/re", url: "https://github.com/acme/re"})

    assert {:ok, 1} = Indexer.index_source(source, dir: dir)
    assert {:ok, 1} = Indexer.index_source(source, dir: dir)

    assert Repo.aggregate(Helmscout.HelmRelease, :count) == 1
  end

  test "a .helmscout-hide-mcp marker flags the source but keeps it indexed", %{dir: dir} do
    source =
      Repo.insert!(%Source{key: "acme/mcp", name: "acme/mcp", url: "https://github.com/acme/mcp"})

    File.write!(Path.join(dir, ".helmscout-hide-mcp"), "")

    assert {:ok, 1} = Indexer.index_source(source, dir: dir)

    reloaded = Repo.get!(Source, source.id)
    assert reloaded.hide_mcp
    assert reloaded.release_count == 1
  end

  test "a helmscout-hide-mcp topic flags the source", %{dir: dir} do
    source =
      Repo.insert!(%Source{
        key: "acme/topic-mcp",
        name: "acme/topic-mcp",
        url: "https://github.com/acme/topic-mcp",
        topics: ["helmscout-hide-mcp"]
      })

    assert {:ok, 1} = Indexer.index_source(source, dir: dir)
    assert Repo.get!(Source, source.id).hide_mcp
  end
end
