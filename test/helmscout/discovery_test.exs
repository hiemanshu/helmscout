defmodule Helmscout.DiscoveryTest do
  use ExUnit.Case, async: true

  alias Helmscout.Discovery

  defp candidate(overrides) do
    Map.merge(
      %{
        name: "owner/repo",
        url: "https://github.com/owner/repo",
        forge: "github",
        branch: "main",
        stars: 0,
        pushed_at: nil,
        topics: [],
        discoverer: "test",
        discoverers: ["test"]
      },
      Map.new(overrides)
    )
  end

  test "merge de-duplicates by lower-cased name and unions metadata" do
    merged =
      Discovery.merge([
        candidate(
          name: "Owner/Repo",
          stars: 5,
          discoverer: "github_topic:flux",
          topics: ["flux"]
        ),
        candidate(name: "owner/repo", stars: 42, discoverer: "curated", topics: ["homelab"])
      ])

    assert [entry] = merged
    assert entry.stars == 42
    assert Enum.sort(entry.discoverers) == ["curated", "github_topic:flux"]
    assert Enum.sort(entry.topics) == ["flux", "homelab"]
  end

  test "merge keeps the most recent push timestamp" do
    old = DateTime.add(DateTime.utc_now(), -400, :day)
    recent = DateTime.add(DateTime.utc_now(), -1, :day)

    [entry] =
      Discovery.merge([
        candidate(name: "a/b", pushed_at: old),
        candidate(name: "a/b", pushed_at: recent, stars: 1)
      ])

    assert DateTime.compare(entry.pushed_at, recent) == :eq
  end

  test "filter_recency drops stale repos but always keeps curated" do
    stale = DateTime.add(DateTime.utc_now(), -300, :day)

    candidates = [
      candidate(name: "stale/repo", pushed_at: stale, discoverer: "github_topic:flux"),
      candidate(
        name: "curated/repo",
        pushed_at: stale,
        discoverer: "curated",
        discoverers: ["curated"]
      ),
      candidate(
        name: "fresh/repo",
        pushed_at: DateTime.utc_now(),
        discoverer: "gitlab_topic:flux"
      )
    ]

    kept = Discovery.filter_recency(candidates, 120) |> Enum.map(& &1.name)
    assert "curated/repo" in kept
    assert "fresh/repo" in kept
    refute "stale/repo" in kept
  end

  test "deny_filter removes chart catalogs" do
    names =
      Discovery.deny_filter([
        candidate(name: "trueforge-org/truecharts"),
        candidate(name: "k8s-at-home/charts"),
        candidate(name: "someone/home-ops")
      ])
      |> Enum.map(& &1.name)

    assert names == ["someone/home-ops"]
  end
end
