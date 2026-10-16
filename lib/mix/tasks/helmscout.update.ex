defmodule Mix.Tasks.Helmscout.Update do
  @shortdoc "Full pipeline: discover, fetch and index"
  @moduledoc """
  Runs the whole pipeline end to end.

      mix helmscout.update --limit 30
      mix helmscout.update --max-age 180 --concurrency 8
      mix helmscout.update --index-only
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    Helmscout.Tasks.ensure_database!()

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          limit: :integer,
          max_age: :integer,
          concurrency: :integer,
          discovery_concurrency: :integer,
          only_stale: :integer,
          topics: :string,
          sources: :string,
          max_pages: :integer,
          index_only: :boolean,
          force: :boolean
        ]
      )

    started = System.monotonic_time(:second)

    stats =
      if opts[:index_only] do
        Helmscout.Pipeline.index_all(
          limit: opts[:limit],
          only_stale_days: opts[:only_stale],
          concurrency: opts[:concurrency] || System.schedulers_online(),
          force: opts[:force] || false
        )
      else
        Helmscout.Pipeline.update(
          limit: opts[:limit],
          max_age_days: opts[:max_age],
          only_stale_days: opts[:only_stale],
          concurrency: opts[:concurrency] || System.schedulers_online(),
          discovery_concurrency: opts[:discovery_concurrency],
          max_pages: opts[:max_pages],
          force: opts[:force] || false,
          topics: split(opts[:topics]),
          sources: atoms(opts[:sources])
        )
      end

    elapsed = System.monotonic_time(:second) - started

    Mix.shell().info("""

    done in #{elapsed}s
      sources:   #{stats[:total]}
      new:       #{stats[:inserted]}
      updated:   #{stats[:updated]}
      indexed:   #{stats[:ok] || 0} ok, #{stats[:empty] || 0} empty, #{stats[:error] || 0} error
      releases:  #{stats[:releases] || 0}
    """)
  end

  defp split(nil), do: nil
  defp split(value), do: value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

  defp atoms(nil), do: nil

  defp atoms(value) do
    map = %{
      "curated" => :curated,
      "users" => :users,
      "github_topics" => :github_topics,
      "github_code" => :github_code,
      "gitlab" => :gitlab,
      "gitea" => :gitea,
      "awesome" => :awesome,
      "helm_repos" => :helm_repos
    }

    value |> split() |> Enum.map(&Map.get(map, &1)) |> Enum.reject(&is_nil/1)
  end
end
