defmodule Helmscout.Discovery.Awesome do
  @moduledoc """
  Scrapes curated awesome lists for GitHub repository links.

  The original `k8s-at-home/awesome-home-kubernetes` list has been deleted, so
  the defaults point at a maintained fork plus the popular `awesome-homelab`
  list. Because general "awesome" lists mostly link to *software* projects
  rather than GitOps cluster repos, collected links are filtered to names that
  look like cluster/home-ops repositories.

  Override the lists entirely with `HELMSCOUT_AWESOME_LISTS` (comma-separated
  raw README URLs).
  """

  require Logger

  alias Helmscout.Http

  @default_lists [
    "https://raw.githubusercontent.com/zacheryph/awesome-home-kubernetes/main/README.md",
    "https://raw.githubusercontent.com/AwesomeHomelab/awesome-homelab/master/README.md"
  ]

  @repo_regex ~r{https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)}

  @non_repos ~w(topics orgs orgs/ sponsoring settings marketplace features collections apps login signup about pricing)

  # Markers that make a repository name look like a GitOps / home-cluster repo,
  # matched against the repo part only (never the owner) to avoid software
  # projects such as `nicolargo/glances` or `miniflux/v2`.
  @gitops_markers ~w(
    home-ops homeops home_ops home-cluster home-cluster home-lab homelab home-infra
    k8s k3s kubernetes gitops cluster infra talos
  )

  @spec candidates(keyword()) :: [map()]
  def candidates(opts \\ []) do
    lists = Keyword.get(opts, :lists) || lists()

    lists
    |> Task.async_stream(&fetch_list/1,
      max_concurrency: length(lists),
      timeout: 60_000,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, repos} -> repos
      _ -> []
    end)
    |> Enum.uniq_by(&String.downcase(&1.name))
  end

  defp fetch_list(url) do
    case Http.get(url) do
      {:ok, body} when is_binary(body) ->
        @repo_regex
        |> Regex.scan(body)
        |> Enum.map(fn [_, full_name] -> full_name end)
        |> Enum.reject(&excluded?/1)
        |> Enum.uniq()
        |> Enum.map(&to_candidate/1)

      {:ok, _} ->
        []

      {:error, reason} ->
        Logger.debug("awesome list #{url} failed: #{inspect(reason)}")
        []
    end
  end

  defp excluded?(full_name) do
    down = String.downcase(full_name)
    repo = down |> String.split("/") |> List.last()

    Enum.any?(@non_repos, &(down == &1 or String.starts_with?(down, &1 <> "/"))) or
      String.contains?(repo, "awesome") or
      not Enum.any?(@gitops_markers, &String.contains?(repo, &1))
  end

  defp to_candidate(full_name) do
    %{
      name: full_name,
      url: "https://github.com/#{full_name}",
      forge: "github",
      branch: "main",
      stars: 0,
      pushed_at: nil,
      topics: [],
      discoverer: "awesome"
    }
  end

  defp lists do
    case System.get_env("HELMSCOUT_AWESOME_LISTS") do
      nil -> @default_lists
      "" -> @default_lists
      value -> value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    end
  end
end
