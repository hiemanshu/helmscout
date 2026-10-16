defmodule Helmscout.Discovery.Curated do
  @moduledoc """
  A hand-maintained seed list of high-quality home-ops repositories.

  These are always included regardless of recency, which keeps well-known but
  occasionally quiet repos in the index and gives the pipeline a reliable floor
  of good data. Additional repositories can be added without code changes by:

    * setting `HELMSCOUT_SEED_REPOS="owner/repo,owner2/repo2"`, or
    * listing them (one per line) in `priv/seed_repos.txt`.
  """

  @built_in ~w(
    onedr0p/home-ops
    bjw-s-labs/home-ops
    bjw-s/home-ops
    billimek/k8s-gitops
    xunholy/k8s-gitops
    toboshii/home-ops
    carpenike/k8s-gitops
    wrmilling/k3s-gitops
    brettinternet/homeops
    buroa/k8s-gitops
    szinn/k8s-homelab
    auricom/home-ops
    ahinko/home-ops
    budimanjojo/home-cluster
    angelnu/k8s-gitops
    joryirving/home-ops
    truxnell/home-cluster
    haraldkoch/kochhaus-home
    ishioni/homelab-ops
    samip5/k8s-cluster
    kashalls/home-cluster
    anthr76/infra
    onedr0p/cluster-template
    rafaribe/home-ops
    mvaldes14/home-ops
  )

  @spec candidates() :: [map()]
  def candidates do
    @built_in
    |> Kernel.++(from_file())
    |> Kernel.++(from_env())
    |> Enum.map(& &1)
    |> Enum.uniq()
    |> Enum.map(&to_candidate/1)
  end

  defp to_candidate(name) do
    %{
      name: name,
      url: "https://github.com/#{name}",
      forge: "github",
      branch: "main",
      stars: 0,
      pushed_at: nil,
      topics: [],
      discoverer: "curated"
    }
  end

  defp from_env do
    case System.get_env("HELMSCOUT_SEED_REPOS") do
      nil -> []
      "" -> []
      value -> value |> String.split([",", "\n"], trim: true) |> Enum.map(&String.trim/1)
    end
  end

  defp from_file do
    path = Path.join(:code.priv_dir(:helmscout), "seed_repos.txt")

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

      _ ->
        []
    end
  end
end
