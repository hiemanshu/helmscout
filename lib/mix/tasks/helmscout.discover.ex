defmodule Mix.Tasks.Helmscout.Discover do
  @shortdoc "Discover source repositories from GitHub/GitLab/Codeberg/awesome lists"
  @moduledoc """
  Runs the discovery sources, merges the results and stores them as sources.

      mix helmscout.discover
      mix helmscout.discover --max-age 180 --topics k8s-at-home,helmscout
      mix helmscout.discover --dry-run
      mix helmscout.discover --sources curated,github_topics
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    Helmscout.Tasks.ensure_database!()

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          max_age: :integer,
          topics: :string,
          sources: :string,
          max_pages: :integer,
          concurrency: :integer,
          dry_run: :boolean
        ]
      )

    run_opts =
      []
      |> maybe_put(:max_age_days, opts[:max_age])
      |> maybe_put(:topics, split(opts[:topics]))
      |> maybe_put(:max_pages, opts[:max_pages])
      |> maybe_put(:concurrency, opts[:concurrency])
      |> maybe_put(:sources, split_atoms(opts[:sources]))

    candidates = Helmscout.Discovery.run(run_opts)

    if opts[:dry_run] do
      Mix.shell().info("\n#{length(candidates)} candidates:")

      Enum.each(candidates, fn c ->
        Mix.shell().info("  #{c.name} (#{c.forge}, #{c.stars} stars)")
      end)
    else
      stats = Helmscout.Discovery.persist(candidates)

      Mix.shell().info(
        "\npersisted: #{stats.total} total (#{stats.inserted} new, #{stats.updated} updated)"
      )
    end
  end

  @source_map %{
    "curated" => :curated,
    "users" => :users,
    "github_topics" => :github_topics,
    "github_code" => :github_code,
    "gitlab" => :gitlab,
    "gitea" => :gitea,
    "awesome" => :awesome,
    "helm_repos" => :helm_repos
  }

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp split(nil), do: nil
  defp split(value), do: value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

  defp split_atoms(nil) do
    nil
  end

  defp split_atoms(value) do
    value
    |> split()
    |> Enum.map(&Map.get(@source_map, &1))
    |> Enum.reject(&is_nil/1)
  end
end
